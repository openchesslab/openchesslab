defmodule SlidingRayVariantsBenchmark do
  import Bitwise

  alias Chess.Bitboard

  @target 28

  def run do
    Benchee.run(
      [
        {"rook: recursive", fn -> benchmark(:rook, :recursive) end},
        {"rook: direct", fn -> benchmark(:rook, :direct) end},
        {"rook: mask", fn -> benchmark(:rook, :mask) end},
        {"bishop: recursive", fn -> benchmark(:bishop, :recursive) end},
        {"bishop: direct", fn -> benchmark(:bishop, :direct) end},
        {"bishop: mask", fn -> benchmark(:bishop, :mask) end}
      ],
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 1
    )
  end

  defp benchmark(:rook, variant) do
    board =
      Bitboard.empty()
      |> Bitboard.put(31, {:black, :rook})

    occupied = Bitboard.occupied(board)

    case variant do
      :recursive ->
        recursive_ray?(board, occupied, @target, 1, :rook)

      :direct ->
        direct_ray?(board, occupied, @target, 1, :rook)

      :mask ->
        mask_ray?(board, occupied, @target, 1, :rook)
    end
  end

  defp benchmark(:bishop, variant) do
    board =
      Bitboard.empty()
      |> Bitboard.put(55, {:black, :bishop})

    occupied = Bitboard.occupied(board)

    case variant do
      :recursive ->
        recursive_ray?(board, occupied, @target, 9, :bishop)

      :direct ->
        direct_ray?(board, occupied, @target, 9, :bishop)

      :mask ->
        mask_ray?(board, occupied, @target, 9, :bishop)
    end
  end

  defp recursive_ray?(board, occupied, square, step, piece_type) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        enemy_piece_on_square?(board, next, piece_type)
      else
        recursive_ray?(board, occupied, next, step, piece_type)
      end
    else
      false
    end
  end

  defp direct_ray?(board, occupied, square, step, piece_type) do
    next = square + step

    cond do
      not valid_ray_square?(square, next, step) ->
        false

      (occupied &&& 1 <<< next) != 0 ->
        enemy_piece_on_square?(board, next, piece_type)

      true ->
        direct_ray?(board, occupied, next, step, piece_type)
    end
  end

  defp mask_ray?(board, occupied, square, step, piece_type) do
    ray_mask = ray_mask(square, step)

    blockers = occupied &&& ray_mask

    case first_blocker(blockers, step) do
      nil ->
        false

      first ->
        enemy_piece_on_square?(board, first, piece_type)
    end
  end

  defp first_blocker(0, _step), do: nil

  defp first_blocker(blockers, step) when step > 0 do
    Enum.find(0..63, fn square ->
      (blockers &&& 1 <<< square) != 0
    end)
  end

  defp first_blocker(blockers, step) when step < 0 do
    Enum.find(63..0//-1, fn square ->
      (blockers &&& 1 <<< square) != 0
    end)
  end

  defp ray_mask(square, step) do
    ray_mask(square, step, 0)
  end

  defp ray_mask(square, step, mask) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      ray_mask(next, step, mask ||| 1 <<< next)
    else
      mask
    end
  end

  defp enemy_piece_on_square?(board, square, :rook) do
    mask = 1 <<< square

    (board.black_rooks &&& mask) != 0 or
      (board.black_queens &&& mask) != 0
  end

  defp enemy_piece_on_square?(board, square, :bishop) do
    mask = 1 <<< square

    (board.black_bishops &&& mask) != 0 or
      (board.black_queens &&& mask) != 0
  end

  defp valid_ray_square?(_from, to, step)
       when step in [8, -8] do
    to in 0..63
  end

  defp valid_ray_square?(from, to, 1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, 9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end
end

SlidingRayVariantsBenchmark.run()
