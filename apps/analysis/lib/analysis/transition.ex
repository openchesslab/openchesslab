defmodule Analysis.Transition do
  @moduledoc """
  Describes how one game-tree occurrence transitions to its child.
  """

  alias Chess.Move

  @type t :: {:move, Move.t()}

  @spec move(Move.t()) :: t()
  def move(%Move{} = move), do: {:move, move}
end
