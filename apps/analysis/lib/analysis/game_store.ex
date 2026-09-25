defmodule Analysis.GameStore do
  @moduledoc false

  alias Analysis.Game

  @default_adapter Analysis.GameStore.Memory
  @default_store Analysis.GameStore.Runtime

  @type store :: GenServer.server()
  @type revision :: pos_integer()

  @callback insert(store(), Game.t()) ::
              {:ok, revision()}
              | {:error, :already_exists}

  @callback get(store(), Game.id()) ::
              {:ok, Game.t(), revision()}
              | :not_found

  @callback list(store()) ::
              [{Game.t(), revision()}]

  @callback update(store(), Game.t(), revision()) ::
              {:ok, revision()}
              | {:error, :not_found | :conflict}

  @callback delete(store(), Game.id(), revision()) ::
              :ok
              | {:error, :not_found | :conflict}

  @spec insert(Game.t()) ::
          {:ok, revision()}
          | {:error, :already_exists}
  def insert(%Game{} = game) do
    adapter().insert(store(), game)
  end

  @spec get(Game.id()) ::
          {:ok, Game.t(), revision()}
          | :not_found
  def get(game_id) do
    adapter().get(store(), game_id)
  end

  @spec list() :: [{Game.t(), revision()}]
  def list do
    adapter().list(store())
  end

  @spec update(Game.t(), revision()) ::
          {:ok, revision()}
          | {:error, :not_found | :conflict}
  def update(%Game{} = game, expected_revision) do
    adapter().update(
      store(),
      game,
      expected_revision
    )
  end

  @spec delete(Game.id(), revision()) ::
          :ok
          | {:error, :not_found | :conflict}
  def delete(game_id, expected_revision) do
    adapter().delete(
      store(),
      game_id,
      expected_revision
    )
  end

  defp adapter do
    config()
    |> Keyword.get(
      :adapter,
      @default_adapter
    )
  end

  defp store do
    config()
    |> Keyword.get(
      :store,
      @default_store
    )
  end

  defp config do
    Application.get_env(
      :analysis,
      __MODULE__,
      []
    )
  end
end
