defmodule Analysis.Node do
  @moduledoc """
  A node in a chess game tree.

  Each node represents one occurrence of a position in the game tree.
  The position itself is stored in PositionDB and is identified by
  `position_id`.

  The root node has no move. Every other node stores the move that led
  from its parent to this node.
  """

  alias Chess.Move

  @type position_id :: term()

  @type t :: %__MODULE__{
          position_id: position_id(),
          move: Move.t() | nil,
          children: [t()]
        }

  @enforce_keys [:position_id]
  defstruct position_id: nil,
            move: nil,
            children: []

  @spec new(position_id()) :: t()
  def new(position_id) do
    %__MODULE__{
      position_id: position_id
    }
  end

  @spec new(position_id(), Move.t()) :: t()
  def new(position_id, move) do
    %__MODULE__{
      position_id: position_id,
      move: move
    }
  end

  @spec position_id(t()) :: position_id()
  def position_id(%__MODULE__{position_id: position_id}) do
    position_id
  end

  @spec move(t()) :: Move.t() | nil
  def move(%__MODULE__{move: move}) do
    move
  end

  @spec children(t()) :: [t()]
  def children(%__MODULE__{children: children}) do
    children
  end

  @spec leaf?(t()) :: boolean()
  def leaf?(%__MODULE__{children: children}) do
    children == []
  end

  @spec main_child(t()) :: t() | nil
  def main_child(%__MODULE__{children: [child | _]}) do
    child
  end

  def main_child(%__MODULE__{children: []}) do
    nil
  end
end
