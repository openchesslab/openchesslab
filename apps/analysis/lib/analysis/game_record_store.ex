defmodule Analysis.GameRecordStore do
  @moduledoc """
  Storage facade for concrete played-game records.

  Game records reference canonical chess content in GameDB through
  their `game_id`.

  The record id identifies the concrete played game. Multiple
  records may therefore reference the same canonical GameDB game.
  """

  alias Analysis.GameRecord

  @default_adapter Analysis.GameRecordStore.Memory

  @registry Analysis.GameRecordStoreRegistry
  @registry_key :game_record_store

  @type store :: GenServer.server()

  @callback insert(
              store(),
              GameRecord.t()
            ) ::
              :ok
              | {:error, :already_exists}

  @callback get(
              store(),
              GameRecord.id()
            ) ::
              {:ok, GameRecord.t()}
              | :not_found

  @callback list(store()) ::
              [GameRecord.t()]

  @callback list_by_game_id(
              store(),
              GameDB.game_id()
            ) ::
              [GameRecord.t()]

  @spec clustered_store() ::
          GenServer.server()
  def clustered_store do
    {
      :via,
      Horde.Registry,
      {
        @registry,
        @registry_key
      }
    }
  end

  @spec ready?() :: boolean()
  def ready? do
    try do
      GenServer.call(
        store(),
        :ping,
        1_000
      ) == :ok
    catch
      :exit, _reason ->
        false
    end
  end

  @spec insert(GameRecord.t()) ::
          :ok
          | {:error, :already_exists}
  def insert(%GameRecord{} = record) do
    adapter().insert(
      store(),
      record
    )
  end

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
  def get(record_id) do
    adapter().get(
      store(),
      record_id
    )
  end

  @spec list() ::
          [GameRecord.t()]
  def list do
    adapter().list(store())
  end

  @spec list_by_game_id(GameDB.game_id()) ::
          [GameRecord.t()]
  def list_by_game_id(game_id) do
    adapter().list_by_game_id(
      store(),
      game_id
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
      clustered_store()
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
