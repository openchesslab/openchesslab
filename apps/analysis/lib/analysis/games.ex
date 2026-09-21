defmodule Analysis.Games do
  @moduledoc false

  alias Analysis.Game
  alias Analysis.GameStore.Memory

  @store Analysis.GameStore.Runtime

  @spec insert(Game.t()) ::
          {:ok, pos_integer()} | {:error, :already_exists}
  def insert(%Game{} = game) do
    Memory.insert(@store, game)
  end

  @spec get(Game.id()) ::
          {:ok, Game.t(), pos_integer()} | :not_found
  def get(game_id) do
    Memory.get(@store, game_id)
  end
end
