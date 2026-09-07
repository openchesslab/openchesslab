defmodule Chess.MapBoard do
  @moduledoc """
  Represents a chess board as a map from squares to pieces.

  Empty squares are not stored in the map.
  """

  @type color :: Chess.Board.color()
  @type piece_type :: Chess.Board.piece_type()
  @type piece :: Chess.Board.piece()
  @type t :: %{optional(Chess.Square.t()) => piece()}

  @spec empty() :: t()
  def empty do
    %{}
  end

  @spec get(t(), Chess.Square.t()) :: piece() | nil
  def get(board, square) when square in 0..63 do
    Map.get(board, square)
  end

  @spec put(t(), Chess.Square.t(), piece()) :: t()
  def put(board, square, piece) when square in 0..63 do
    Map.put(board, square, piece)
  end

  @spec remove(t(), Chess.Square.t()) :: t()
  def remove(board, square) when square in 0..63 do
    Map.delete(board, square)
  end

  @spec pieces(t()) :: [{Chess.Square.t(), piece()}]
  def pieces(board) do
    board
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
  end
end
