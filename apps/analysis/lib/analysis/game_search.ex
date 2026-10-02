defmodule Analysis.GameSearch do
  @moduledoc """
  PostgreSQL-native bounded search across canonical positions,
  game occurrences and concrete game records.

  A search page is one joined PostgreSQL query. Pagination uses a
  stateless compound keyset cursor and captures high-water marks when
  the first page is read, excluding later inserts from the same scan.
  """

  alias Analysis.GameOccurrence
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch.PostgresQuery
  alias Analysis.GameStart
  alias Analysis.PositionQuery
  alias Analysis.PositionQueryNormalizer
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :maximum_position_id,
      :maximum_occurrence_id,
      :maximum_record_row_id,
      :last_position_id,
      :last_occurrence_id,
      :last_record_row_id
    ]

    defstruct [
      :maximum_position_id,
      :maximum_occurrence_id,
      :maximum_record_row_id,
      :last_position_id,
      :last_occurrence_id,
      :last_record_row_id
    ]

    @type t :: %__MODULE__{
            maximum_position_id: non_neg_integer(),
            maximum_occurrence_id: non_neg_integer(),
            maximum_record_row_id: non_neg_integer(),
            last_position_id: pos_integer(),
            last_occurrence_id: pos_integer(),
            last_record_row_id: pos_integer()
          }
  end

  defmodule Page do
    @moduledoc false

    @enforce_keys [
      :entries
    ]

    defstruct entries: [],
              next: nil

    @type t :: %__MODULE__{
            entries: [Analysis.GameSearch.occurrence_match()],
            next:
              Analysis.GameSearch.cursor()
              | nil
          }
  end

  @type occurrence_match ::
          {GameRecord.t(), GameOccurrence.t()}

  @opaque cursor :: Cursor.t()

  @type page_result ::
          {:ok, Page.t()}
          | {:error, term()}

  @spec page(
          PositionQuery.t(),
          keyword()
        ) ::
          page_result()
  def page(position_query, options) when is_list(options) do
    page(
      position_query,
      GameRecordQuery.match_all(),
      options
    )
  end

  @spec page(
          PositionQuery.t(),
          GameRecordQuery.t(),
          keyword()
        ) ::
          page_result()
  def page(position_query, record_query, options) when is_list(options) do
    normalized_position_query =
      PositionQueryNormalizer.normalize(position_query)

    with {:ok, limit} <-
           fetch_limit(options),
         {:ok, cursor} <-
           fetch_cursor(options) do
      do_page(
        normalized_position_query,
        record_query,
        limit,
        cursor
      )
    end
  end

  def page(_position_query, _record_query, _options) do
    {:error, :invalid_page_options}
  end

  defp do_page(false, _record_query, _limit, _cursor) do
    empty_page()
  end

  defp do_page(_position_query, false, _limit, _cursor) do
    empty_page()
  end

  defp do_page(position_query, record_query, limit, nil) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           PostgresQuery.compile_first(
             position_query,
             record_query,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      {
        :ok,
        build_page(
          rows,
          limit
        )
      }
    end
  end

  defp do_page(position_query, record_query, limit, %Cursor{} = cursor) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           PostgresQuery.compile_next(
             position_query,
             record_query,
             cursor.maximum_position_id,
             cursor.maximum_occurrence_id,
             cursor.maximum_record_row_id,
             cursor.last_position_id,
             cursor.last_occurrence_id,
             cursor.last_record_row_id,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      {
        :ok,
        build_page(
          rows,
          limit
        )
      }
    end
  end

  defp build_page(rows, limit) when length(rows) <= limit do
    %Page{
      entries:
        Enum.map(
          rows,
          &match_from_row/1
        )
    }
  end

  defp build_page(rows, limit) do
    {
      page_rows,
      _remaining_rows
    } =
      Enum.split(
        rows,
        limit
      )

    %Page{
      entries:
        Enum.map(
          page_rows,
          &match_from_row/1
        ),
      next:
        page_rows
        |> List.last()
        |> cursor_from_row()
    }
  end

  defp cursor_from_row([
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

  defp fetch_limit(options) do
    case Keyword.fetch(
           options,
           :limit
         ) do
      {:ok, limit}
      when is_integer(limit) and limit > 0 ->
        {:ok, limit}

      {:ok, _limit} ->
        {:error, :invalid_limit}

      :error ->
        {:error, :missing_limit}
    end
  end

  defp fetch_cursor(options) do
    case Keyword.get(
           options,
           :cursor
         ) do
      nil ->
        {:ok, nil}

      %Cursor{} = cursor ->
        {:ok, cursor}

      _cursor ->
        {:error, :invalid_cursor}
    end
  end

  defp empty_page do
    {
      :ok,
      %Page{
        entries: []
      }
    }
  end
end
