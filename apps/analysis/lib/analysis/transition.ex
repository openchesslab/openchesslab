defmodule Analysis.Transition do
  @moduledoc """
  Describes how one game-tree occurrence transitions to its child.
  """

  alias Chess.Move

  @type t ::
          {:move, Move.t()}
          | :edit

  @spec move(Move.t()) :: t()
  def move(%Move{} = move), do: {:move, move}

  @spec edit() :: t()
  def edit, do: :edit
end
