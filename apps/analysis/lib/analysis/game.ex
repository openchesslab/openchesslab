defmodule Analysis.Game do
  @moduledoc """
  A chess game with metadata, an initial position, and a main variation.
  """

  alias Analysis.Variation

  @type position_id :: term()

  @type t :: %__MODULE__{
          initial_position_id: position_id(),
          metadata: map(),
          main_variation: Variation.t()
        }

  @enforce_keys [:initial_position_id]
  defstruct initial_position_id: nil,
            metadata: %{},
            main_variation: Variation.new()

  @spec new(position_id()) :: t()
  def new(initial_position_id) do
    %__MODULE__{
      initial_position_id: initial_position_id
    }
  end

  @spec new(position_id(), map()) :: t()
  def new(initial_position_id, metadata) when is_map(metadata) do
    %__MODULE__{
      initial_position_id: initial_position_id,
      metadata: metadata
    }
  end
end
