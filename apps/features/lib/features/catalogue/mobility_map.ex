defmodule Features.Catalogue.MobilityMap do
  @moduledoc """
  Shared mobility analysis: legal and pseudo-legal move counts per piece
  and per side.

  Mobility of the side to move is computed from its legal moves; the
  opponent's mobility comes from pseudo-legal generation on a
  side-flipped copy of the board.
  """

  alias Features.Chess.{Board, Movegen}

  @doc "Legal moves for the side to move."
  @spec legal_moves(Board.t()) :: [Features.Chess.Move.t()]
  def legal_moves(board), do: Movegen.legal_moves(board)

  @doc "Number of legal moves for the side to move."
  @spec legal_count(Board.t()) :: non_neg_integer()
  def legal_count(board), do: board |> legal_moves() |> length()

  @doc "Pseudo-legal moves available to `color`."
  @spec pseudo_moves(Board.t(), atom()) :: [Features.Chess.Move.t()]
  def pseudo_moves(board, color) do
    if board.side_to_move == color do
      Movegen.pseudo_legal_moves(board)
    else
      Movegen.pseudo_legal_moves(%{board | side_to_move: color})
    end
  end

  @doc "Pseudo-legal move count per origin square for `color`."
  @spec piece_counts(Board.t(), atom()) :: %{non_neg_integer() => pos_integer()}
  def piece_counts(board, color) do
    board
    |> pseudo_moves(color)
    |> Enum.frequencies_by(& &1.from)
  end

  @doc "Distinct destination-square count per origin square for `color`."
  @spec available_counts(Board.t(), atom()) :: %{non_neg_integer() => pos_integer()}
  def available_counts(board, color) do
    board
    |> pseudo_moves(color)
    |> Enum.group_by(& &1.from, & &1.to)
    |> Map.new(fn {from, targets} -> {from, targets |> Enum.uniq() |> length()} end)
  end

  @doc "Total pseudo-legal move count for `color`."
  @spec total(Board.t(), atom()) :: non_neg_integer()
  def total(board, color), do: board |> pseudo_moves(color) |> length()
end
