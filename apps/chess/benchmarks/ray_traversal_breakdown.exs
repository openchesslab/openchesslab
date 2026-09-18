defmodule RayTraversalBreakdownBenchmark do
  import Bitwise

  alias Chess.Bitboard

  # e4
  @origin 28

  def run do
    Benchee.run(
      [
        {"rook: 0 empty squares", fn ->
          benchmark_ray(:rook, [])
        end},
        {"rook: 1 empty square", fn ->
          benchmark_ray(:rook, [29])
        end},
        {"rook: 2 empty squares", fn ->
          benchmark_ray(:rook, [29, 30])
        end},
        {"rook: 3 empty squares", fn ->
          benchmark_ray(:rook, [29, 30, 31])
        end},

        {"bishop: 0 empty squares", fn ->
          benchmark_ray(:bishop, [])
        end},
        {"bishop: 1 empty square", fn ->
          benchmark_ray(:bishop, [37])
        end},
        {"bishop: 2 empty squares", fn ->
          benchmark_ray(:bishop, [37, 46])
        end},
        {"bishop: 3 empty squares", fn ->
          benchmark_ray(:bishop, [37, 46, 55])
        end},

        {"rook: 3 empty squares + blocker", fn ->
          benchmark_blocker(:rook, [29, 30, 31])
        end},
        {"bishop: 3 empty squares + blocker", fn ->
          benchmark_blocker(:bishop, [37, 46, 55])
        end}
      ],
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 1
    )
  end

  defp benchmark_ray(type, empty_squares) do
    target = target_square(type)

    board =
      Bitboard.empty()
      |> Bitboard.put(target, {:black, piece_type(type)})

    occupied = Bitboard.occupied(board)

    ray_attacked?(
      board,
      occupied,
      @origin,
      step(type),
      :black,
      piece_type(type)
    )
  end

  defp benchmark_blocker(type, empty_squares) do
    target = target_square(type)

    board =
      Enum.reduce(empty_squares, Bitboard.empty(), fn square, board ->
        Bitboard.put(board, square, {:white, :pawn})
      end)
      |> Bitboard.put(target, {:black, piece_type(type)})

    occupied = Bitboard.occupied(board)

    ray_attacked?(
      board,
      occupied,
      @origin,
      step(type),
      :black,
      piece_type(type)
    )
  end

  # e4 -> h4
  defp target_square(:rook), do: 31

  # e4 -> h7
  defp target_square(:bishop), do: 55

  defp step(:rook), do: 1
  defp step(:bishop), do: 9

  defp piece_type(:rook), do: :rook
  defp piece_type(:bishop), do: :bishop

  defp ray_attacked?(
         board,
         occupied,
         square,
         step,
         color,
         piece_type
       ) do
    first_piece_on_ray(
      board,
      occupied,
      square,
      step,
      color,
      piece_type
    )
  end

  defp first_piece_on_ray(
         board,
         occupied,
         square,
         step,
         color,
         piece_type
       ) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_type do
          :rook ->
            (color_rooks(board, color) &&& mask) != 0 or
              (color_queens(board, color) &&& mask) != 0

          :bishop ->
            (color_bishops(board, color) &&& mask) != 0 or
              (color_queens(board, color) &&& mask) != 0
        end
      else
        first_piece_on_ray(
          board,
          occupied,
          next,
          step,
          color,
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
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -1) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, 9) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp color_rooks(board, :white), do: board.white_rooks
  defp color_rooks(board, :black), do: board.black_rooks

  defp color_queens(board, :white), do: board.white_queens
  defp color_queens(board, :black), do: board.black_queens

  defp color_bishops(board, :white), do: board.white_bishops
  defp color_bishops(board, :black), do: board.black_bishops
end

RayTraversalBreakdownBenchmark.run()
