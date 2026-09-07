defmodule Chess.Bitboard do
  @moduledoc """
  Represents a chess board using one 64-bit bitboard per piece type and color.
  """

  import Bitwise

  @type piece_type :: Chess.Board.piece_type()
  @type color :: Chess.Board.color()
  @type piece :: Chess.Board.piece()

  @type t :: %__MODULE__{
          white_pawns: non_neg_integer(),
          white_knights: non_neg_integer(),
          white_bishops: non_neg_integer(),
          white_rooks: non_neg_integer(),
          white_queens: non_neg_integer(),
          white_king: non_neg_integer(),
          black_pawns: non_neg_integer(),
          black_knights: non_neg_integer(),
          black_bishops: non_neg_integer(),
          black_rooks: non_neg_integer(),
          black_queens: non_neg_integer(),
          black_king: non_neg_integer()
        }

  defstruct [
    :white_pawns,
    :white_knights,
    :white_bishops,
    :white_rooks,
    :white_queens,
    :white_king,
    :black_pawns,
    :black_knights,
    :black_bishops,
    :black_rooks,
    :black_queens,
    :black_king
  ]

  @spec empty() :: t()
  def empty do
    %__MODULE__{
      white_pawns: 0,
      white_knights: 0,
      white_bishops: 0,
      white_rooks: 0,
      white_queens: 0,
      white_king: 0,
      black_pawns: 0,
      black_knights: 0,
      black_bishops: 0,
      black_rooks: 0,
      black_queens: 0,
      black_king: 0
    }
  end

  @spec from_position(Chess.Position.t()) :: t()
  def from_position(%Chess.Position{board: board}) do
    board
    |> Chess.Board.pieces()
    |> Enum.reduce(empty(), &put_piece/2)
  end

  defp put_piece({square, {color, piece_type}}, board) do
    mask = Bitwise.bsl(1, square)

    case {color, piece_type} do
      {:white, :pawn} ->
        %{board | white_pawns: Bitwise.bor(board.white_pawns, mask)}

      {:white, :knight} ->
        %{board | white_knights: Bitwise.bor(board.white_knights, mask)}

      {:white, :bishop} ->
        %{board | white_bishops: Bitwise.bor(board.white_bishops, mask)}

      {:white, :rook} ->
        %{board | white_rooks: Bitwise.bor(board.white_rooks, mask)}

      {:white, :queen} ->
        %{board | white_queens: Bitwise.bor(board.white_queens, mask)}

      {:white, :king} ->
        %{board | white_king: Bitwise.bor(board.white_king, mask)}

      {:black, :pawn} ->
        %{board | black_pawns: Bitwise.bor(board.black_pawns, mask)}

      {:black, :knight} ->
        %{board | black_knights: Bitwise.bor(board.black_knights, mask)}

      {:black, :bishop} ->
        %{board | black_bishops: Bitwise.bor(board.black_bishops, mask)}

      {:black, :rook} ->
        %{board | black_rooks: Bitwise.bor(board.black_rooks, mask)}

      {:black, :queen} ->
        %{board | black_queens: Bitwise.bor(board.black_queens, mask)}

      {:black, :king} ->
        %{board | black_king: Bitwise.bor(board.black_king, mask)}
    end
  end

  @spec get(t(), Chess.Square.t()) :: piece() | nil
  def get(board, square) when square in 0..63 do
    mask = 1 <<< square

    Enum.find_value(piece_fields(), fn {color, type, field} ->
      if band(Map.fetch!(board, field), mask) != 0 do
        {color, type}
      end
    end)
  end

  @spec put(t(), Chess.Square.t(), piece()) :: t()
  def put(board, square, {color, type})
      when square in 0..63 do
    board
    |> remove(square)
    |> set_piece(square, color, type)
  end

  @spec remove(t(), Chess.Square.t()) :: t()
  def remove(board, square) when square in 0..63 do
    mask = bnot(1 <<< square)

    Enum.reduce(piece_fields(), board, fn {_color, _type, field}, board ->
      Map.update!(board, field, &band(&1, mask))
    end)
  end

  @spec pieces(t()) :: [{Chess.Square.t(), piece()}]
  def pieces(board) do
    for square <- 0..63,
        piece = get(board, square),
        piece != nil do
      {square, piece}
    end
  end

  @spec white_pieces(t()) :: non_neg_integer()
  def white_pieces(board) do
    board.white_pawns
    |> bor(board.white_knights)
    |> bor(board.white_bishops)
    |> bor(board.white_rooks)
    |> bor(board.white_queens)
    |> bor(board.white_king)
  end

  @spec black_pieces(t()) :: non_neg_integer()
  def black_pieces(board) do
    board.black_pawns
    |> bor(board.black_knights)
    |> bor(board.black_bishops)
    |> bor(board.black_rooks)
    |> bor(board.black_queens)
    |> bor(board.black_king)
  end

  @spec occupied(t()) :: non_neg_integer()
  def occupied(board) do
    board
    |> white_pieces()
    |> bor(black_pieces(board))
  end

  @spec count_pieces(non_neg_integer()) :: non_neg_integer()
  def count_pieces(bitboard) do
    popcount(bitboard)
  end

  @spec swap_colors(t()) :: t()
  def swap_colors(board) do
    %__MODULE__{
      white_pawns: board.black_pawns,
      white_knights: board.black_knights,
      white_bishops: board.black_bishops,
      white_rooks: board.black_rooks,
      white_queens: board.black_queens,
      white_king: board.black_king,
      black_pawns: board.white_pawns,
      black_knights: board.white_knights,
      black_bishops: board.white_bishops,
      black_rooks: board.white_rooks,
      black_queens: board.white_queens,
      black_king: board.white_king
    }
  end

  defp popcount(value) do
    popcount(value, 0)
  end

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(value &&& value - 1, count + 1)
  end

  defp set_piece(board, square, color, type) do
    field = field_for(color, type)
    mask = 1 <<< square

    Map.update!(board, field, &bor(&1, mask))
  end

  defp field_for(:white, :pawn), do: :white_pawns
  defp field_for(:white, :knight), do: :white_knights
  defp field_for(:white, :bishop), do: :white_bishops
  defp field_for(:white, :rook), do: :white_rooks
  defp field_for(:white, :queen), do: :white_queens
  defp field_for(:white, :king), do: :white_king

  defp field_for(:black, :pawn), do: :black_pawns
  defp field_for(:black, :knight), do: :black_knights
  defp field_for(:black, :bishop), do: :black_bishops
  defp field_for(:black, :rook), do: :black_rooks
  defp field_for(:black, :queen), do: :black_queens
  defp field_for(:black, :king), do: :black_king

  defp piece_fields do
    [
      {:white, :pawn, :white_pawns},
      {:white, :knight, :white_knights},
      {:white, :bishop, :white_bishops},
      {:white, :rook, :white_rooks},
      {:white, :queen, :white_queens},
      {:white, :king, :white_king},
      {:black, :pawn, :black_pawns},
      {:black, :knight, :black_knights},
      {:black, :bishop, :black_bishops},
      {:black, :rook, :black_rooks},
      {:black, :queen, :black_queens},
      {:black, :king, :black_king}
    ]
  end
end
