defmodule Analysis.TransitionNotation do
  @moduledoc """
  Formats transitions between game-tree occurrences.

  Move transitions use canonical SAN. Edit transitions do not have
  chess notation.
  """

  alias Analysis.Transition
  alias Chess.Notation.SAN
  alias Chess.Position

  @spec format(Position.t(), Transition.t()) ::
          {:ok, String.t()} | :not_applicable | {:error, :illegal_move}
  def format(%Position{} = position, {:move, move}) do
    SAN.format(position, move)
  end

  def format(%Position{}, :edit) do
    :not_applicable
  end
end
