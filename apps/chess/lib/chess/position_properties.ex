defmodule Chess.PositionProperties do
  @moduledoc """
  Derived properties of a chess position.
  """

  alias Chess.Bitboard
  alias Chess.Position

  @piece_types [:pawn, :knight, :bishop, :rook, :queen, :king]

  @files [:a, :b, :c, :d, :e, :f, :g, :h]

  @file_masks %{
    a: 0x0101010101010101,
    b: 0x0202020202020202,
    c: 0x0404040404040404,
    d: 0x0808080808080808,
    e: 0x1010101010101010,
    f: 0x2020202020202020,
    g: 0x4040404040404040,
    h: 0x8080808080808080
  }

  @spec open_files(Position.t()) :: [atom()]
  def open_files(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> open_files()
  end

  @spec open_files(Bitboard.t()) :: [atom()]
  def open_files(%Bitboard{} = board) do
    pawn_files = Bitwise.bor(board.white_pawns, board.black_pawns)

    Enum.filter(@files, fn file ->
      Bitwise.band(pawn_files, @file_masks[file]) == 0
    end)
  end

  @type material :: %{
          white: %{Chess.Board.piece_type() => non_neg_integer()},
          black: %{Chess.Board.piece_type() => non_neg_integer()}
        }

  @spec material(Position.t()) :: material()
  def material(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> material()
  end

  @spec material(Bitboard.t()) :: material()
  def material(%Bitboard{} = board) do
    %{
      white: material_for_color(board, :white),
      black: material_for_color(board, :black)
    }
  end

  @spec occupied(Position.t()) :: non_neg_integer()
  def occupied(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> occupied()
  end

  @spec occupied(Bitboard.t()) :: non_neg_integer()
  def occupied(%Bitboard{} = board) do
    Bitboard.occupied(board)
  end

  defp material_for_color(board, color) do
    Map.new(@piece_types, fn piece_type ->
      {piece_type, count(board, color, piece_type)}
    end)
  end

  defp count(board, color, piece_type) do
    board
    |> piece_bitboard(color, piece_type)
    |> popcount()
  end

  defp piece_bitboard(board, :white, :pawn), do: board.white_pawns
  defp piece_bitboard(board, :white, :knight), do: board.white_knights
  defp piece_bitboard(board, :white, :bishop), do: board.white_bishops
  defp piece_bitboard(board, :white, :rook), do: board.white_rooks
  defp piece_bitboard(board, :white, :queen), do: board.white_queens
  defp piece_bitboard(board, :white, :king), do: board.white_king

  defp piece_bitboard(board, :black, :pawn), do: board.black_pawns
  defp piece_bitboard(board, :black, :knight), do: board.black_knights
  defp piece_bitboard(board, :black, :bishop), do: board.black_bishops
  defp piece_bitboard(board, :black, :rook), do: board.black_rooks
  defp piece_bitboard(board, :black, :queen), do: board.black_queens
  defp piece_bitboard(board, :black, :king), do: board.black_king

  defp popcount(value), do: popcount(value, 0)

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(Bitwise.band(value, value - 1), count + 1)
  end
end
