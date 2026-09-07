alias Chess.Bitboard
alias Chess.Board
alias Chess.MapBoard

import Bitwise

defmodule BenchmarkHelpers do
  import Bitwise

  def popcount(value) do
    popcount(value, 0)
  end

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(value &&& value - 1, count + 1)
  end
end

pieces = [
  {0, {:white, :rook}},
  {1, {:white, :knight}},
  {2, {:white, :bishop}},
  {3, {:white, :queen}},
  {4, {:white, :king}},
  {5, {:white, :bishop}},
  {6, {:white, :knight}},
  {7, {:white, :rook}},
  {8, {:white, :pawn}},
  {9, {:white, :pawn}},
  {10, {:white, :pawn}},
  {11, {:white, :pawn}},
  {12, {:white, :pawn}},
  {13, {:white, :pawn}},
  {14, {:white, :pawn}},
  {15, {:white, :pawn}},
  {48, {:black, :pawn}},
  {49, {:black, :pawn}},
  {50, {:black, :pawn}},
  {51, {:black, :pawn}},
  {52, {:black, :pawn}},
  {53, {:black, :pawn}},
  {54, {:black, :pawn}},
  {55, {:black, :pawn}},
  {56, {:black, :rook}},
  {57, {:black, :knight}},
  {58, {:black, :bishop}},
  {59, {:black, :queen}},
  {60, {:black, :king}},
  {61, {:black, :bishop}},
  {62, {:black, :knight}},
  {63, {:black, :rook}}
]

tuple_board =
  Enum.reduce(pieces, Board.empty(), fn {square, piece}, board ->
    Board.put(board, square, piece)
  end)

map_board =
  Enum.reduce(pieces, MapBoard.empty(), fn {square, piece}, board ->
    MapBoard.put(board, square, piece)
  end)

bitboard =
  Enum.reduce(pieces, Bitboard.empty(), fn {square, piece}, board ->
    Bitboard.put(board, square, piece)
  end)

e_file_mask =
  Enum.reduce(0..7, 0, fn rank, mask ->
    bor(mask, 1 <<< (rank * 8 + 4))
  end)

tuple_occupied = fn ->
  tuple_board
  |> Board.pieces()
  |> Enum.map(&elem(&1, 0))
end

map_occupied = fn ->
  map_board
  |> MapBoard.pieces()
  |> Enum.map(&elem(&1, 0))
end

bitboard_occupied = fn ->
  Bitboard.occupied(bitboard)
end

tuple_white_occupied = fn ->
  tuple_board
  |> Board.pieces()
  |> Enum.filter(fn {_square, {color, _piece}} -> color == :white end)
  |> Enum.map(&elem(&1, 0))
end

map_white_occupied = fn ->
  map_board
  |> MapBoard.pieces()
  |> Enum.filter(fn {_square, {color, _piece}} -> color == :white end)
  |> Enum.map(&elem(&1, 0))
end

bitboard_white_occupied = fn ->
  Bitboard.white_pieces(bitboard)
end

tuple_material = fn ->
  tuple_board
  |> Board.pieces()
  |> Enum.frequencies_by(fn {_square, piece} -> piece end)
end

map_material = fn ->
  map_board
  |> MapBoard.pieces()
  |> Enum.frequencies_by(fn {_square, piece} -> piece end)
end

bitboard_material = fn ->
  %{
    white_pawns: BenchmarkHelpers.popcount(bitboard.white_pawns),
    white_knights: BenchmarkHelpers.popcount(bitboard.white_knights),
    white_bishops: BenchmarkHelpers.popcount(bitboard.white_bishops),
    white_rooks: BenchmarkHelpers.popcount(bitboard.white_rooks),
    white_queens: BenchmarkHelpers.popcount(bitboard.white_queens),
    black_pawns: BenchmarkHelpers.popcount(bitboard.black_pawns),
    black_knights: BenchmarkHelpers.popcount(bitboard.black_knights),
    black_bishops: BenchmarkHelpers.popcount(bitboard.black_bishops),
    black_rooks: BenchmarkHelpers.popcount(bitboard.black_rooks),
    black_queens: BenchmarkHelpers.popcount(bitboard.black_queens)
  }
end

tuple_open_file = fn ->
  tuple_board
  |> Board.pieces()
  |> Enum.all?(fn
    {square, {_color, :pawn}} ->
      band(e_file_mask, 1 <<< square) == 0

    {_square, _piece} ->
      true
  end)
end

map_open_file = fn ->
  map_board
  |> MapBoard.pieces()
  |> Enum.all?(fn
    {square, {_color, :pawn}} ->
      band(e_file_mask, 1 <<< square) == 0

    {_square, _piece} ->
      true
  end)
end

bitboard_open_file = fn ->
  pawns = bor(bitboard.white_pawns, bitboard.black_pawns)
  band(pawns, e_file_mask) == 0
end

Benchee.run(
  %{
    "tuple occupied" => tuple_occupied,
    "map occupied" => map_occupied,
    "bitboard occupied" => bitboard_occupied,
    "tuple white occupied" => tuple_white_occupied,
    "map white occupied" => map_white_occupied,
    "bitboard white occupied" => bitboard_white_occupied,
    "tuple material" => tuple_material,
    "map material" => map_material,
    "bitboard material" => bitboard_material,
    "tuple open e-file" => tuple_open_file,
    "map open e-file" => map_open_file,
    "bitboard open e-file" => bitboard_open_file
  },
  time: 5,
  memory_time: 2
)
