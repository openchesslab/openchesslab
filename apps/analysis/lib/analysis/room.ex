defmodule Analysis.Room do
  @moduledoc false

  @type id :: term()
  @type game_id :: Analysis.Game.id()

  @type t :: %__MODULE__{
          id: id(),
          game_ids: [game_id()]
        }

  @enforce_keys [:id]
  defstruct id: nil, game_ids: []

  @spec new(id()) :: t()
  def new(id) do
    %__MODULE__{id: id}
  end

  @spec id(t()) :: id()
  def id(%__MODULE__{id: id}) do
    id
  end

  @spec game_ids(t()) :: [game_id()]
  def game_ids(%__MODULE__{game_ids: game_ids}) do
    game_ids
  end

  @spec has_game?(t(), game_id()) :: boolean()
  def has_game?(%__MODULE__{game_ids: game_ids}, game_id) do
    game_id in game_ids
  end

  @spec add_game(t(), game_id()) :: t()
  def add_game(%__MODULE__{} = room, game_id) do
    if has_game?(room, game_id) do
      room
    else
      %{room | game_ids: room.game_ids ++ [game_id]}
    end
  end

  @spec remove_game(t(), game_id()) :: t()
  def remove_game(%__MODULE__{} = room, game_id) do
    %{
      room
      | game_ids:
          Enum.reject(
            room.game_ids,
            &(&1 == game_id)
          )
    }
  end
end
