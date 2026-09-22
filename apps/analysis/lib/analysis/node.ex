defmodule Analysis.Node do
  @moduledoc """
  A node in a chess game tree.

  Each node represents one occurrence of a position in the game tree.
  The position itself is stored in PositionDB and is identified by
  `position_id`.

  The root node has no transition. Every other node stores the transition
  that led from its parent to this node.
  """

  alias Analysis.Transition

  @type position_id :: term()

  @type t :: %__MODULE__{
          position_id: position_id(),
          transition: Transition.t() | nil,
          comment: String.t() | nil,
          children: [t()]
        }

  @enforce_keys [:position_id]
  defstruct position_id: nil,
            transition: nil,
            comment: nil,
            children: []

  @spec new(position_id()) :: t()
  def new(position_id) do
    %__MODULE__{
      position_id: position_id
    }
  end

  @spec new(position_id(), Transition.t()) :: t()
  def new(position_id, transition) do
    %__MODULE__{
      position_id: position_id,
      transition: transition
    }
  end

  @spec position_id(t()) :: position_id()
  def position_id(%__MODULE__{position_id: position_id}) do
    position_id
  end

  @spec transition(t()) :: Transition.t() | nil
  def transition(%__MODULE__{transition: transition}) do
    transition
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

  @spec child_index(t(), Transition.t(), position_id()) ::
          non_neg_integer() | nil
  def child_index(
        %__MODULE__{children: children},
        transition,
        position_id
      ) do
    Enum.find_index(children, fn child ->
      transition(child) == transition and
        position_id(child) == position_id
    end)
  end

  @spec comment(t()) :: String.t() | nil
  def comment(%__MODULE__{comment: comment}) do
    comment
  end
end
