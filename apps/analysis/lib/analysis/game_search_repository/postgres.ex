defmodule Analysis.GameSearchRepository.Postgres do
  @moduledoc """
  PostgreSQL-native bounded game search.

  Position predicates, game occurrences and concrete game-record predicates
  are executed in one joined PostgreSQL query.

  Paging is stateless keyset paging over the ordered result key
  `{position_id, occurrence_id, game_record_row_id}`.

  The first query captures high-water marks for positions, occurrences and
  game-record rows in the same PostgreSQL statement. Rows inserted after that
  statement are therefore excluded from subsequent pages.
  """

  @behaviour Analysis.GameSearchRepository

  alias Analysis.GameOccurrence
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameSearchRepository.Postgres.QueryCompiler
  alias Analysis.GameStart
  alias Analysis.PositionQuery
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    alias Analysis.GameRecordQuery
    alias Analysis.PositionQuery

    @enforce_keys [
      :position_query,
      :record_query,
      :maximum_position_id,
      :maximum_occurrence_id,
      :maximum_record_row_id,
      :last_position_id,
      :last_occurrence_id,
      :last_record_row_id
    ]

    defstruct [
      :position_query,
      :record_query,
      :maximum_position_id,
      :maximum_occurrence_id,
      :maximum_record_row_id,
      :last_position_id,
      :last_occurrence_id,
      :last_record_row_id
    ]

    @type t :: %__MODULE__{
            position_query: PositionQuery.t(),
            record_query: GameRecordQuery.t(),
            maximum_position_id: non_neg_integer(),
            maximum_occurrence_id: non_neg_integer(),
            maximum_record_row_id: non_neg_integer(),
            last_position_id: pos_integer(),
            last_occurrence_id: pos_integer(),
            last_record_row_id: pos_integer()
          }
  end

  @type query_cursor :: Cursor.t()

  @impl Analysis.GameSearchRepository
  def query_page(false, _record_query, page_size) when is_integer(page_size) and page_size > 0 do
    {
      :ok,
      [],
      :done
    }
  end

  def query_page(_position_query, false, page_size)
      when is_integer(page_size) and page_size > 0 do
    {
      :ok,
      [],
      :done
    }
  end

  def query_page(position_query, record_query, page_size)
      when is_integer(page_size) and page_size > 0 do
    requested_rows =
      page_size + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           QueryCompiler.compile_first(
             position_query,
             record_query,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      build_page(
        position_query,
        record_query,
        rows,
        page_size
      )
    end
  end

  def query_page(_position_query, _record_query, _page_size) do
    {:error, :invalid_query_page}
  end

  @impl Analysis.GameSearchRepository
  def next_query_page(
        %Cursor{
          position_query: position_query,
          record_query: record_query,
          maximum_position_id: maximum_position_id,
          maximum_occurrence_id: maximum_occurrence_id,
          maximum_record_row_id: maximum_record_row_id,
          last_position_id: last_position_id,
          last_occurrence_id: last_occurrence_id,
          last_record_row_id: last_record_row_id
        },
        page_size
      )
      when is_integer(page_size) and page_size > 0 do
    requested_rows =
      page_size + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           QueryCompiler.compile_next(
             position_query,
             record_query,
             maximum_position_id,
             maximum_occurrence_id,
             maximum_record_row_id,
             last_position_id,
             last_occurrence_id,
             last_record_row_id,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      build_page(
        position_query,
        record_query,
        rows,
        page_size
      )
    end
  end

  def next_query_page(_cursor, _page_size) do
    {:error, :cursor_not_found}
  end

  @impl Analysis.GameSearchRepository
  def close_query(%Cursor{}) do
    :ok
  end

  def close_query(_cursor) do
    :ok
  end

  defp build_page(_position_query, _record_query, rows, page_size)
       when length(rows) <= page_size do
    {
      :ok,
      Enum.map(
        rows,
        &match_from_row/1
      ),
      :done
    }
  end

  defp build_page(position_query, record_query, rows, page_size) do
    {
      page_rows,
      _remaining_rows
    } =
      Enum.split(
        rows,
        page_size
      )

    cursor =
      cursor_from_row(
        position_query,
        record_query,
        List.last(page_rows)
      )

    {
      :ok,
      Enum.map(
        page_rows,
        &match_from_row/1
      ),
      cursor
    }
  end

  defp cursor_from_row(position_query, record_query, [
         maximum_position_id,
         maximum_occurrence_id,
         maximum_record_row_id,
         position_id,
         occurrence_id,
         _occurrence_game_id,
         _ply,
         record_row_id,
         _record_id,
         _record_game_id,
         _fullmove_number,
         _metadata
       ]) do
    %Cursor{
      position_query: position_query,
      record_query: record_query,
      maximum_position_id: maximum_position_id,
      maximum_occurrence_id: maximum_occurrence_id,
      maximum_record_row_id: maximum_record_row_id,
      last_position_id: position_id,
      last_occurrence_id: occurrence_id,
      last_record_row_id: record_row_id
    }
  end

  defp match_from_row([
         _maximum_position_id,
         _maximum_occurrence_id,
         _maximum_record_row_id,
         position_id,
         occurrence_id,
         occurrence_game_id,
         ply,
         _record_row_id,
         record_id,
         record_game_id,
         fullmove_number,
         metadata
       ]) do
    record =
      GameRecord.new(
        record_id,
        record_game_id,
        GameStart.new(fullmove_number),
        metadata
      )

    occurrence =
      GameOccurrence.new(
        occurrence_id,
        occurrence_game_id,
        ply,
        position_id
      )

    {
      record,
      occurrence
    }
  end
end
