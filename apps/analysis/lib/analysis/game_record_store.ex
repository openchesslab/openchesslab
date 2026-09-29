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

  @opaque record_cursor :: reference()

  @type record_page ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}

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

  @callback records_page_by_game_id(
              store(),
              GameDB.game_id(),
              pos_integer()
            ) ::
              record_page()

  @callback next_records_page(
              store(),
              record_cursor(),
              pos_integer()
            ) ::
              record_page()

  @callback close_record_scan(
              store(),
              record_cursor()
            ) ::
              :ok

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
    rescue
      ArgumentError ->
        false
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

  @spec records_page_by_game_id(
          GameDB.game_id(),
          pos_integer()
        ) ::
          record_page()
  def records_page_by_game_id(
        game_id,
        page_size
      )
      when is_integer(page_size) and
             page_size > 0 do
    adapter().records_page_by_game_id(
      store(),
      game_id,
      page_size
    )
  end

  @spec next_records_page(
          record_cursor(),
          pos_integer()
        ) ::
          record_page()
  def next_records_page(
        cursor,
        page_size
      )
      when is_reference(cursor) and
             is_integer(page_size) and
             page_size > 0 do
    adapter().next_records_page(
      store(),
      cursor,
      page_size
    )
  end

  @spec close_record_scan(record_cursor()) ::
          :ok
  def close_record_scan(cursor)
      when is_reference(cursor) do
    adapter().close_record_scan(
      store(),
      cursor
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
