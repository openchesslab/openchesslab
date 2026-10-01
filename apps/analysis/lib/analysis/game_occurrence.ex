defmodule Analysis.GameOccurrence do
  @moduledoc """
  One occurrence of a canonical chess position in a canonical game.

  Occurrences have their own stable identity because the same position can
  occur more than once in one game and across many different games.
  """

  @type id :: pos_integer()
  @type game_id :: pos_integer()
  @type position_id :: pos_integer()
  @type ply :: non_neg_integer()

  @type t :: %__MODULE__{
          id: id(),
          game_id: game_id(),
          ply: ply(),
          position_id: position_id()
        }

  @enforce_keys [
    :id,
    :game_id,
    :ply,
    :position_id
  ]

  defstruct [
    :id,
    :game_id,
    :ply,
    :position_id
  ]

  @spec new(
          id(),
          game_id(),
          ply(),
          position_id()
        ) :: t()
  def new(id, game_id, ply, position_id)
      when is_integer(id) and id > 0 and is_integer(game_id) and game_id > 0 and is_integer(ply) and
             ply >= 0 and is_integer(position_id) and position_id > 0 do
    %__MODULE__{
      id: id,
      game_id: game_id,
      ply: ply,
      position_id: position_id
    }
  end
end
