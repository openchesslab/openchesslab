defmodule Chess.Board do
  @moduledoc """
  Represents a chess board as a tuple of 64 squares.

  Squares are indexed according to `Chess.Square`:

      a1 = 0
      b1 = 1
      ...
      h8 = 63

  An empty square contains `nil`.
  """

  @type color :: :white | :black

  @type piece_type ::
          :king
          | :queen
          | :rook
          | :bishop
          | :knight
          | :pawn

  @type piece :: {color(), piece_type()}

  @type t :: tuple()

  @size 64

  @spec empty() :: t()
  def empty do
    :erlang.make_tuple(@size, nil)
  end

  @spec get(t(), Chess.Square.t()) :: piece() | nil
  def get(board, square) when square in 0..63 do
    elem(board, square)
  end

  @spec put(t(), Chess.Square.t(), piece()) :: t()
  def put(board, square, piece)
      when square in 0..63 do
    put_elem(board, square, piece)
  end

  @spec remove(t(), Chess.Square.t()) :: t()
  def remove(board, square) when square in 0..63 do
    put_elem(board, square, nil)
  end

  @spec pieces(t()) :: [{Chess.Square.t(), piece()}]
  def pieces(board) do
    board
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reject(fn {piece, _square} -> is_nil(piece) end)
    |> Enum.map(fn {piece, square} -> {square, piece} end)
  end
end
