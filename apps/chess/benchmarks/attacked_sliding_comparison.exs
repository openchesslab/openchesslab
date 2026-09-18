defmodule AttackedSlidingComparisonBenchmark do
  import Bitwise

  alias Chess.Bitboard

  @target 28

  def run do
    Benchee.run(
      [
        {"rook open: ray", fn -> benchmark_ray(:rook, :open) end},
        {"rook open: attacks", fn -> benchmark_attacks(:rook, :open) end},
        {"rook blocked: ray", fn -> benchmark_ray(:rook, :blocked) end},
        {"rook blocked: attacks", fn -> benchmark_attacks(:rook, :blocked) end},
        {"bishop open: ray", fn -> benchmark_ray(:bishop, :open) end},
        {"bishop open: attacks", fn -> benchmark_attacks(:bishop, :open) end},
        {"bishop blocked: ray", fn -> benchmark_ray(:bishop, :blocked) end},
        {"bishop blocked: attacks", fn -> benchmark_attacks(:bishop, :blocked) end}
      ],
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 1
    )
  end

  defp benchmark_ray(:rook, :open) do
    board =
      Bitboard.empty()
      |> Bitboard.put(31, {:black, :rook})

    occupied = Bitboard.occupied(board)

    ray_attacked_rook?(board, occupied, @target)
  end

  defp benchmark_ray(:rook, :blocked) do
    board =
      Bitboard.empty()
      |> Bitboard.put(30, {:white, :pawn})
      |> Bitboard.put(31, {:black, :rook})

    occupied = Bitboard.occupied(board)

    ray_attacked_rook?(board, occupied, @target)
  end

  defp benchmark_ray(:bishop, :open) do
    board =
      Bitboard.empty()
      |> Bitboard.put(55, {:black, :bishop})

    occupied = Bitboard.occupied(board)

    ray_attacked_bishop?(board, occupied, @target)
  end

  defp benchmark_ray(:bishop, :blocked) do
    board =
      Bitboard.empty()
      |> Bitboard.put(46, {:white, :pawn})
      |> Bitboard.put(55, {:black, :bishop})

    occupied = Bitboard.occupied(board)

    ray_attacked_bishop?(board, occupied, @target)
  end

  defp benchmark_attacks(:rook, :open) do
    board =
      Bitboard.empty()
      |> Bitboard.put(31, {:black, :rook})

    attacks = Bitboard.rook_attacks(board, @target)
    target = 1 <<< @target

    (attacks &&& target) != 0
  end

  defp benchmark_attacks(:rook, :blocked) do
    board =
      Bitboard.empty()
      |> Bitboard.put(30, {:white, :pawn})
      |> Bitboard.put(31, {:black, :rook})

    attacks = Bitboard.rook_attacks(board, @target)
    target = 1 <<< @target

    (attacks &&& target) != 0
  end

  defp benchmark_attacks(:bishop, :open) do
    board =
      Bitboard.empty()
      |> Bitboard.put(55, {:black, :bishop})

    attacks = Bitboard.bishop_attacks(board, @target)
    target = 1 <<< @target

    (attacks &&& target) != 0
  end

  defp benchmark_attacks(:bishop, :blocked) do
    board =
      Bitboard.empty()
      |> Bitboard.put(46, {:white, :pawn})
      |> Bitboard.put(55, {:black, :bishop})

    attacks = Bitboard.bishop_attacks(board, @target)
    target = 1 <<< @target

    (attacks &&& target) != 0
  end

  defp ray_attacked_rook?(board, occupied, square) do
    ray_attacked?(board, occupied, square, [8, -8, 1, -1], :rook)
  end

  defp ray_attacked_bishop?(board, occupied, square) do
    ray_attacked?(board, occupied, square, [9, 7, -7, -9], :bishop)
  end

  defp ray_attacked?(board, occupied, square, steps, piece_type) do
    Enum.any?(steps, fn step ->
      first_piece_on_ray(
        board,
        occupied,
        square,
        step,
        piece_type
      )
    end)
  end

  defp first_piece_on_ray(
         board,
         occupied,
         square,
         step,
         piece_type
       ) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_type do
          :rook ->
            (board.black_rooks &&& mask) != 0 or
              (board.black_queens &&& mask) != 0

          :bishop ->
            (board.black_bishops &&& mask) != 0 or
              (board.black_queens &&& mask) != 0
        end
      else
        first_piece_on_ray(
          board,
          occupied,
          next,
          step,
          piece_type
        )
      end
    else
      false
    end
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

AttackedSlidingComparisonBenchmark.run()
