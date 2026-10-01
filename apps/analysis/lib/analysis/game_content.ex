defmodule Analysis.GameContent do
  @moduledoc """
  The canonical chess content of a played game.

  Game content defines chess identity independently of the concrete
  game record. Player names, event information, result, source and
  move-number context do not contribute to this identity.
  """

  alias Chess.Move

  @type position_id :: pos_integer()

  @type t :: %__MODULE__{
          initial_position_id: position_id(),
          moves: [Move.t()]
        }

  @enforce_keys [
    :initial_position_id,
    :moves
  ]

  defstruct [
    :initial_position_id,
    moves: []
  ]

  @spec new(
          position_id(),
          [Move.t()]
        ) :: t()
  def new(initial_position_id, moves \\ []) when is_list(moves) do
    %__MODULE__{
      initial_position_id: initial_position_id,
      moves: moves
    }
  end

  @spec initial_position_id(t()) :: position_id()
  def initial_position_id(%__MODULE__{initial_position_id: initial_position_id}) do
    initial_position_id
  end

  @spec moves(t()) :: [Move.t()]
  def moves(%__MODULE__{moves: moves}) do
    moves
  end
end
