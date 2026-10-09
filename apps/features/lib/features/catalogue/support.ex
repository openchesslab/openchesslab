defmodule Features.Catalogue.Support do
  @moduledoc """
  Shared geometry and counting helpers used by catalogue feature modules.
  All helpers are pure functions over `Features.Chess.Board`.
  """

  import Bitwise

  alias Features.Chess.{AttackTables, Bitboard, Board, Square}

  @type color_name :: String.t()

  @values %{pawn: 1, knight: 3, bishop: 3, rook: 5, queen: 9, king: 0}

  @singular %{
    pawns: :pawn,
    knights: :knight,
    bishops: :bishop,
    rooks: :rook,
    queens: :queen,
    kings: :king
  }

  @type_names %{
    pawns: "pawn",
    knights: "knight",
    bishops: "bishop",
    rooks: "rook",
    queens: "queen",
    kings: "king"
  }

  @color_names %{white: "white", black: "black"}

  @doc "Game-theoretic pawn-unit value per singular piece type."
  @spec values() :: %{atom() => number()}
  def values, do: @values

  @doc "Singular English name for a stored piece type atom."
  @spec type_name(atom()) :: String.t()
  def type_name(type), do: Map.fetch!(@type_names, type)

  @doc "English color name."
  @spec color_name(atom()) :: color_name()
  def color_name(color), do: Map.fetch!(@color_names, color)

  @doc "Algebraic strings for every set square, ascending."
  @spec squares(non_neg_integer()) :: [String.t()]
  def squares(bitboard) do
    bitboard
    |> Bitboard.squares()
    |> Enum.map(&Square.to_string/1)
  end

  @doc "Bitboard of one file (0 = a .. 7 = h)."
  @spec file_bb(0..7) :: non_neg_integer()
  def file_bb(file), do: 0x0101010101010101 <<< file

  @doc "Bitboard of one rank (0 = first .. 7 = eighth)."
  @spec rank_bb(0..7) :: non_neg_integer()
  def rank_bb(rank), do: 0xFF <<< (rank * 8)

  @doc "Bitboard of the half of the board `color` attacks into."
  @spec enemy_half_bb(atom()) :: non_neg_integer()
  def enemy_half_bb(:white), do: 0xFFFFFFFF00000000
  def enemy_half_bb(:black), do: 0x00000000FFFFFFFF

  @doc "Bitboard of the big center c3-f6."
  @spec center_bb() :: non_neg_integer()
  def center_bb do
    Enum.reduce(2..5, 0, fn file, files -> files ||| file_bb(file) end) &&&
      Enum.reduce(2..5, 0, fn rank, ranks -> ranks ||| rank_bb(rank) end)
  end

  @doc "Bitboard of the four key central squares d4, e4, d5, e5."
  @spec key_center_bb() :: non_neg_integer()
  def key_center_bb do
    (rank_bb(3) ||| rank_bb(4)) &&& (file_bb(3) ||| file_bb(4))
  end

  @doc "Lowercase file letter for a file index."
  @spec file_letter(0..7) :: String.t()
  def file_letter(file), do: <<?a + file>>

  @doc "Number of set bits."
  @spec popcount(non_neg_integer()) :: non_neg_integer()
  def popcount(bitboard), do: length(Bitboard.squares(bitboard))

  @doc "Count of `type` pieces for `color`."
  @spec piece_count(Board.t(), atom(), atom()) :: non_neg_integer()
  def piece_count(board, color, type), do: popcount(Board.piece_bb(board, color, type))

  @doc "All piece-type counts for one color, keyed by singular names."
  @spec piece_counts(Board.t(), atom()) :: %{String.t() => non_neg_integer()}
  def piece_counts(board, color) do
    for type <- Board.types(), into: %{} do
      {type_name(type), piece_count(board, color, type)}
    end
  end

  @doc "Total material for one color in pawn units."
  @spec material_value(Board.t(), atom()) :: non_neg_integer()
  def material_value(board, color) do
    Enum.reduce(Board.types(), 0, fn type, acc ->
      acc + piece_count(board, color, type) * Map.fetch!(@values, Map.fetch!(@singular, type))
    end)
  end

  @doc "Combined knight and bishop count."
  @spec minor_count(Board.t(), atom()) :: non_neg_integer()
  def minor_count(board, color),
    do: piece_count(board, color, :knights) + piece_count(board, color, :bishops)

  @doc "Board color of a square: `:dark` on a1-style squares, `:light` otherwise."
  @spec square_color(integer()) :: :dark | :light
  def square_color(square) do
    if rem(Square.file(square) + Square.rank(square), 2) == 0, do: :dark, else: :light
  end

  @doc "Set of square colors occupied by `color`'s bishops."
  @spec bishop_colors(Board.t(), atom()) :: MapSet.t(:dark | :light)
  def bishop_colors(board, color) do
    board
    |> Board.piece_bb(color, :bishops)
    |> Bitboard.squares()
    |> MapSet.new(&square_color/1)
  end

  @doc "Whether `square` is attacked by a pawn of `color`."
  @spec attacked_by_pawn?(Board.t(), non_neg_integer(), atom()) :: boolean()
  def attacked_by_pawn?(board, square, color) do
    (AttackTables.pawn_attackers(color, square) &&& Board.piece_bb(board, color, :pawns)) != 0
  end

  @doc """
  Own pawns grouped by file index, ranks sorted ascending
  (rank 0 = first rank for both colors).
  """
  @spec pawns_by_file(Board.t(), atom()) :: %{non_neg_integer() => [non_neg_integer()]}
  def pawns_by_file(board, color) do
    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.group_by(&Square.file/1, &Square.rank/1)
    |> Map.new(fn {file, ranks} -> {file, Enum.sort(ranks)} end)
  end

  @doc """
  Passed pawns for `color`: no enemy pawn on the same or either adjacent
  file ahead of the pawn.
  """
  @spec passed_pawns(Board.t(), atom()) :: [non_neg_integer()]
  def passed_pawns(board, color) do
    enemy_pawns = Board.piece_bb(board, Board.opposite(color), :pawns)

    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.filter(fn square ->
      file = Square.file(square)
      rank = Square.rank(square)

      enemy_pawns
      |> Bitboard.squares()
      |> Enum.all?(fn enemy ->
        enemy_file = Square.file(enemy)
        enemy_rank = Square.rank(enemy)

        abs(enemy_file - file) > 1 or not ahead?(enemy_rank, rank, color)
      end)
    end)
  end

  @doc "Whether a pawn of `color` can advance one or two squares (ignoring king safety)."
  @spec can_advance?(Board.t(), non_neg_integer()) :: boolean()
  def can_advance?(board, square) do
    color =
      case Board.piece_at(board, square) do
        {color, :pawns} -> color
        _ -> nil
      end

    if color == nil do
      false
    else
      step = if color == :white, do: 8, else: -8
      target = square + step

      target in 0..63 and Board.piece_at(board, target) == nil
    end
  end

  defp ahead?(enemy_rank, rank, :white), do: enemy_rank > rank
  defp ahead?(enemy_rank, rank, :black), do: enemy_rank < rank
end
