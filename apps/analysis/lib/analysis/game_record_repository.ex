defmodule Analysis.GameRecordRepository do
  @moduledoc """
  Persistence contract for concrete played-game records.

  A game record references durable canonical game content through its
  `game_id`.

  Repository implementations own durable record identity and bounded
  paging of records belonging to one canonical game.
  """

  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameStore

  @type record_id :: GameRecord.id()
  @type record_cursor :: term()

  @type record_page ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}
  @type query_cursor :: term()

  @type query_page ::
          {:ok, [GameRecord.t()], :done | query_cursor()}
          | {:error, term()}

  @callback ready?() :: boolean()

  @callback insert(GameRecord.t()) ::
              :ok
              | {:error, term()}

  @callback get(record_id()) ::
              {:ok, GameRecord.t()}
              | :not_found
              | {:error, term()}

  @callback records_page_by_game_id(
              GameStore.game_id(),
              pos_integer()
            ) :: record_page()

  @callback records_page_by_game_id(
              GameStore.game_id(),
              GameRecordQuery.t(),
              pos_integer()
            ) :: record_page()

  @callback next_records_page(
              record_cursor(),
              pos_integer()
            ) :: record_page()

  @callback close_records(record_cursor()) :: :ok

  @callback query_page(
              GameRecordQuery.t(),
              pos_integer()
            ) :: query_page()

  @callback next_query_page(
              query_cursor(),
              pos_integer()
            ) :: query_page()

  @callback close_query(query_cursor()) :: :ok
end
