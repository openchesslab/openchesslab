defmodule Analysis.GameSearch do
  @moduledoc """
  PostgreSQL-native bounded search across canonical positions,
  game occurrences and concrete game records.

  A search page is one joined PostgreSQL query. Pagination uses a
  stateless compound keyset cursor and captures high-water marks when
  the first page is read, excluding later inserts from the same scan.

  Two orders exist. The default `:insertion` order drives the scan from
  the position side and supports every position predicate. `:date_desc`
  pages newest-first directly from `game_records` (one row per record,
  the first occurrence joined for the preview) and is only defined for
  game-only searches — with a position predicate it returns
  `{:error, :unsupported_sort}` rather than materializing the whole
  position-driven join per page.
  """

  alias Analysis.FeatureDigest
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
      :last_record_row_id,
      :last_date,
      :last_shared
    ]

    @type t :: %__MODULE__{
            maximum_position_id: non_neg_integer(),
            maximum_occurrence_id: non_neg_integer(),
            maximum_record_row_id: non_neg_integer(),
            last_position_id: pos_integer() | nil,
            last_occurrence_id: pos_integer() | nil,
            last_record_row_id: pos_integer(),
            last_date: String.t() | nil,
            last_shared: non_neg_integer() | nil
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
          {GameRecord.t(), GameOccurrence.t() | nil}

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
           fetch_cursor(options),
         {:ok, sort} <-
           fetch_sort(options) do
      search_type = search_type(normalized_position_query)

      :telemetry.span(
        [:openchesslab, :search, :page],
        %{search_type: search_type},
        fn ->
          result =
            do_page(
              normalized_position_query,
              record_query,
              limit,
              cursor,
              sort
            )

          {result, %{search_type: search_type}}
        end
      )
    end
  end

  def page(_position_query, _record_query, _options) do
    {:error, :invalid_page_options}
  end

  @doc """
  Search games reaching positions similar to `position`: the same pawn
  skeleton within one structural edit plus the same material (the
  prefilter), ranked by how many of the position's digest atoms they share
  (the rerank). Keyset-paged by (shared, position id, occurrence id,
  record row id).
  """
  @spec similar(Chess.Position.t(), GameRecordQuery.t(), keyword()) :: page_result()
  def similar(%Chess.Position{} = position, record_query, options) when is_list(options) do
    with {:ok, limit} <- fetch_limit(options),
         {:ok, cursor} <- fetch_cursor(options),
         {:ok, query_atoms} <- similar_query_atoms(position) do
      :telemetry.span(
        [:openchesslab, :search, :page],
        %{search_type: :similar},
        fn ->
          result = do_similar(position, query_atoms, record_query, limit, cursor)
          {result, %{search_type: :similar}}
        end
      )
    end
  end

  def similar(_position, _record_query, _options) do
    {:error, :invalid_page_options}
  end

  # The full atom set ranks candidates; the material signatures prefilter.
  defp similar_query_atoms(position) do
    with {:ok, result} <- Analysis.PositionFeatures.extract(position) do
      atoms = FeatureDigest.atoms(result.features)
      signatures = Enum.filter(atoms, &String.starts_with?(&1, "material.signature:"))
      {:ok, %{atoms: atoms, signatures: signatures}}
    end
  end

  defp do_similar(_position, _query_atoms, _record_query, _limit, %Cursor{last_shared: nil}) do
    {:error, :invalid_cursor}
  end

  defp do_similar(position, query_atoms, record_query, limit, cursor) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           PostgresQuery.compile_similar(
             position,
             query_atoms.signatures,
             query_atoms.atoms,
             record_query,
             cursor,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      {
        :ok,
        build_similar_page(
          rows,
          limit
        )
      }
    end
  end

  @doc """
  Number of concrete game records in the corpus, for the search UI's honest
  scope note. An exact count is cheap at the current corpus size; revisit
  (estimate or counter table) before this gets called per-open at 10M+ rows.
  """
  @spec corpus_size() :: non_neg_integer()
  def corpus_size do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM game_records")
    count
  end

  defp do_page(false, _record_query, _limit, _cursor, _sort) do
    empty_page()
  end

  defp do_page(_position_query, false, _limit, _cursor, _sort) do
    empty_page()
  end

  # Newest-first paging drives from game_records (one row per record) and only
  # exists without a position predicate: sorting the position-driven join
  # would materialize the whole match set per page.
  defp do_page(position_query, _record_query, _limit, _cursor, :date_desc)
       when position_query != true do
    {:error, :unsupported_sort}
  end

  defp do_page(true, _record_query, _limit, %Cursor{last_date: nil}, :date_desc) do
    {:error, :invalid_cursor}
  end

  defp do_page(true, record_query, limit, nil, :date_desc) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           PostgresQuery.compile_date_first(
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
        build_date_page(
          rows,
          limit
        )
      }
    end
  end

  defp do_page(true, record_query, limit, %Cursor{} = cursor, :date_desc) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           PostgresQuery.compile_date_next(
             record_query,
             cursor.maximum_record_row_id,
             cursor.last_date,
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
        build_date_page(
          rows,
          limit
        )
      }
    end
  end

  defp do_page(position_query, record_query, limit, nil, :insertion) do
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

  defp do_page(position_query, record_query, limit, %Cursor{} = cursor, :insertion) do
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

  # The date-sorted path pages game_records directly, one row per record with
  # the first occurrence joined for the preview (records without moves get an
  # honest nil). Undated records coalesce to "" and sort last.
  defp build_similar_page(rows, limit) when length(rows) <= limit do
    %Page{
      entries:
        Enum.map(
          rows,
          &similar_match_from_row/1
        )
    }
  end

  defp build_similar_page(rows, limit) do
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
          &similar_match_from_row/1
        ),
      next:
        page_rows
        |> List.last()
        |> similar_cursor_from_row()
    }
  end

  defp similar_cursor_from_row([
         maximum_position_id,
         maximum_occurrence_id,
         maximum_record_row_id,
         shared,
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
      last_record_row_id: record_row_id,
      last_shared: shared
    }
  end

  defp similar_match_from_row([
         _maximum_position_id,
         _maximum_occurrence_id,
         _maximum_record_row_id,
         shared,
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
      occurrence,
      shared
    }
  end

  defp build_date_page(rows, limit) when length(rows) <= limit do
    %Page{
      entries:
        Enum.map(
          rows,
          &date_match_from_row/1
        )
    }
  end

  defp build_date_page(rows, limit) do
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
          &date_match_from_row/1
        ),
      next:
        page_rows
        |> List.last()
        |> date_cursor_from_row()
    }
  end

  defp date_cursor_from_row([
         maximum_record_row_id,
         record_row_id,
         _record_id,
         _record_game_id,
         _fullmove_number,
         metadata,
         _occurrence_id,
         _ply,
         _position_id
       ]) do
    %Cursor{
      maximum_position_id: 0,
      maximum_occurrence_id: 0,
      maximum_record_row_id: maximum_record_row_id,
      last_position_id: nil,
      last_occurrence_id: nil,
      last_record_row_id: record_row_id,
      last_date: Map.get(metadata, "date") || ""
    }
  end

  defp date_match_from_row([
         _maximum_record_row_id,
         _record_row_id,
         record_id,
         record_game_id,
         fullmove_number,
         metadata,
         occurrence_id,
         ply,
         position_id
       ]) do
    record =
      GameRecord.new(
        record_id,
        record_game_id,
        GameStart.new(fullmove_number),
        metadata
      )

    occurrence =
      if occurrence_id do
        GameOccurrence.new(
          occurrence_id,
          record_game_id,
          ply,
          position_id
        )
      end

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

  # :insertion is the position-driven scan order; :date_desc is the
  # record-driven newest-first order for game-only searches.
  defp fetch_sort(options) do
    case Keyword.get(
           options,
           :sort,
           :insertion
         ) do
      :insertion ->
        {:ok, :insertion}

      :date_desc ->
        {:ok, :date_desc}

      _sort ->
        {:error, :invalid_sort}
    end
  end

  # The search shape, for the latency metric's bounded label.
  defp search_type(true), do: :games
  defp search_type(false), do: :games
  defp search_type({:equivalent, _position}), do: :exact
  defp search_type({:digests, _atoms}), do: :digest

  defp search_type({:and, queries}) do
    if Enum.any?(queries, &match?({:digests, _}, &1)),
      do: :digest,
      else: :combined
  end

  defp search_type({:or, queries}) do
    if Enum.all?(queries, &match?({:equivalent, _}, &1)),
      do: :exact,
      else: :combined
  end

  defp search_type(_query), do: :structure

  defp empty_page do
    {
      :ok,
      %Page{
        entries: []
      }
    }
  end
end
