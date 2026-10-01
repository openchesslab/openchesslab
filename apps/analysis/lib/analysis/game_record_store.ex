defmodule Analysis.GameRecordStore do
  @moduledoc """
  Application-facing access to concrete played-game records.

  Game-record persistence is PostgreSQL-backed and stateless at the
  application layer. The configured repository owns durable record
  identity and bounded record paging.
  """

  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordRepository
  alias Analysis.GameRecordRepository.Postgres
  alias Analysis.GameRepository

  @type record_cursor :: GameRecordRepository.record_cursor()

  @type record_page ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}
  @type query_cursor :: GameRecordRepository.query_cursor()

  @type query_page ::
          {:ok, [GameRecord.t()], :done | query_cursor()}
          | {:error, term()}

  @spec repository() :: module()
  def repository do
    Application.get_env(
      :analysis,
      :game_record_repository,
      Postgres
    )
  end

  @spec ready?() :: boolean()
  def ready? do
    repository().ready?()
  end

  @spec insert(GameRecord.t()) ::
          :ok
          | {:error, term()}
  def insert(%GameRecord{} = record) do
    repository().insert(record)
  end

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
          | {:error, term()}
  def get(record_id) do
    repository().get(record_id)
  end

  @spec records_page_by_game_id(
          GameRepository.game_id(),
          pos_integer()
        ) :: record_page()
  def records_page_by_game_id(game_id, page_size) when is_integer(page_size) and page_size > 0 do
    repository().records_page_by_game_id(
      game_id,
      page_size
    )
  end

  @spec next_records_page(
          record_cursor(),
          pos_integer()
        ) :: record_page()
  def next_records_page(cursor, page_size) when is_integer(page_size) and page_size > 0 do
    repository().next_records_page(
      cursor,
      page_size
    )
  end

  @spec close_record_scan(record_cursor()) :: :ok
  def close_record_scan(cursor) do
    repository().close_records(cursor)
  end

  @spec query_page(
          GameRecordQuery.t(),
          pos_integer()
        ) :: query_page()
  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    repository().query_page(
      query,
      page_size
    )
  end

  @spec next_query_page(
          query_cursor(),
          pos_integer()
        ) :: query_page()
  def next_query_page(cursor, page_size) when is_integer(page_size) and page_size > 0 do
    repository().next_query_page(
      cursor,
      page_size
    )
  end

  @spec close_query(query_cursor()) :: :ok
  def close_query(cursor) do
    repository().close_query(cursor)
  end
end
