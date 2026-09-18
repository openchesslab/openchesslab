defmodule Analysis.Transition do
  @moduledoc """
  A directed transition from one position to another.

  A transition connects two positions through a chess move.
  Position existence and persistence are responsibilities of other layers.
  """

  alias Chess.Move

  @type position_id :: term()

  @type t :: %__MODULE__{
          from_position_id: position_id(),
          move: Move.t(),
          to_position_id: position_id()
        }

  @enforce_keys [:from_position_id, :move, :to_position_id]
  defstruct [:from_position_id, :move, :to_position_id]

  @spec new(position_id(), Move.t(), position_id()) :: t()
  def new(from_position_id, move, to_position_id) do
    %__MODULE__{
      from_position_id: from_position_id,
      move: move,
      to_position_id: to_position_id
    }
  end
end
