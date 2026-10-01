defmodule Analysis.PositionStore do
  @moduledoc """
  Application-facing access to canonical chess positions.

  Position persistence is PostgreSQL-backed and stateless at the
  application layer. The configured repository owns durable identity,
  derived features and bounded position queries.
  """

  alias Analysis.PositionQuery
  alias Analysis.PositionRepository
  alias Analysis.PositionRepository.Postgres
  alias Chess.Position

  @type position_id :: PositionRepository.position_id()
  @type query_cursor :: PositionRepository.query_cursor()

  @type query_page ::
          {:ok, [position_id()], :done | query_cursor()}
          | {:error, term()}

  @spec repository() :: module()
  def repository do
    Application.get_env(
      :analysis,
      :position_repository,
      Postgres
    )
  end

  @spec ready?() :: boolean()
  def ready? do
    repository().ready?()
  end

  @spec get(position_id()) ::
          {:ok, Position.t()}
          | :not_found
          | {:error, term()}
  def get(position_id) do
    repository().get(position_id)
  end

  @spec find(Position.t()) ::
          {:ok, position_id()}
          | :not_found
          | {:error, term()}
  def find(position) do
    repository().find(position)
  end

  @spec query_page(
          PositionQuery.t(),
          pos_integer()
        ) ::
          query_page()
  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    repository().query_page(
      query,
      page_size
    )
  end

  @spec next_query_page(
          query_cursor(),
          pos_integer()
        ) ::
          query_page()
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

  @spec append(Position.t()) ::
          position_id()
          | {:error, term()}
  def append(position) do
    case repository().put(position) do
      {:ok, position_id} ->
        position_id

      {:error, reason} ->
        {:error, reason}
    end
  end
end
