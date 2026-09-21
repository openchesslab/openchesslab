alias Chess.Bitboard
alias Chess.Position

import Bitwise

defmodule RayPieceLookupBenchmark do
  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def starting_board do
    Position.starting_position()
    |> Bitboard.from_position()
  end

  def middlegame_board do
    Position.starting_position()
    |> apply_moves([
      {"e2", "e4"},
      {"e7", "e5"},
      {"g1", "f3"},
      {"b8", "c6"},
      {"f1", "b5"},
      {"a7", "a6"},
      {"b5", "a4"},
      {"g8", "f6"},
      {"e1", "g1"},
      {"f8", "e7"}
    ])
    |> Bitboard.from_position()
  end

  # Current implementation: find the piece through Bitboard.get/2.
  def current(board, square, color, piece_types) do
    case Bitboard.get(board, square) do
      {^color, piece_type} ->
        piece_type in piece_types

      _ ->
        false
    end
  end

  # Specialized implementation for rook/queen rays.
  def rook_or_queen(board, square, color) do
    mask = 1 <<< square

    band(color_rooks(board, color), mask) != 0 or
      band(color_queens(board, color), mask) != 0
  end

  # Specialized implementation for bishop/queen rays.
  def bishop_or_queen(board, square, color) do
    mask = 1 <<< square

    band(color_bishops(board, color), mask) != 0 or
      band(color_queens(board, color), mask) != 0
  end

  defp color_rooks(board, :white), do: board.white_rooks
  defp color_rooks(board, :black), do: board.black_rooks

  defp color_bishops(board, :white), do: board.white_bishops
  defp color_bishops(board, :black), do: board.black_bishops

  defp color_queens(board, :white), do: board.white_queens
  defp color_queens(board, :black), do: board.black_queens

  defp apply_moves(position, moves) do
    Enum.reduce(moves, position, fn {from, to}, position ->
      {:ok, position} =
        Position.apply_move(
          position,
          Chess.Move.new(square(from), square(to))
        )

      position
    end)
  end
end

starting = RayPieceLookupBenchmark.starting_board()
middlegame = RayPieceLookupBenchmark.middlegame_board()

# These are deliberately occupied squares, because this is the case
# encountered by first_piece_on_ray/5.
starting_squares = %{
  "white rook a1" => {starting, "a1", :white},
  "white bishop c1" => {starting, "c1", :white},
  "white queen d1" => {starting, "d1", :white},
  "black rook a8" => {starting, "a8", :black},
  "black bishop c8" => {starting, "c8", :black},
  "black queen d8" => {starting, "d8", :black}
}

middlegame_squares = %{
  "white rook a1" => {middlegame, "a1", :white},
  "white bishop a4" => {middlegame, "a4", :white},
  "white queen d1" => {middlegame, "d1", :white},
  "black rook a8" => {middlegame, "a8", :black},
  "black bishop e7" => {middlegame, "e7", :black},
  "black queen d8" => {middlegame, "d8", :black}
}

benchmarks =
  starting_squares
  |> Enum.flat_map(fn {name, {board, algebraic, color}} ->
    square = RayPieceLookupBenchmark.square(algebraic)

    [
      {"starting #{name}: get rook/queen",
       fn ->
         RayPieceLookupBenchmark.current(board, square, color, [:rook, :queen])
       end},
      {"starting #{name}: mask rook/queen",
       fn ->
         RayPieceLookupBenchmark.rook_or_queen(board, square, color)
       end},
      {"starting #{name}: get bishop/queen",
       fn ->
         RayPieceLookupBenchmark.current(board, square, color, [:bishop, :queen])
       end},
      {"starting #{name}: mask bishop/queen",
       fn ->
         RayPieceLookupBenchmark.bishop_or_queen(board, square, color)
       end}
    ]
  end)
  |> Map.new()

Benchee.run(
  benchmarks,
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
