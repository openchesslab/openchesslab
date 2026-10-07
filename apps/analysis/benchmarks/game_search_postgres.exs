alias Analysis.GameSearchPostgresBenchmark, as: Benchmark

Logger.configure(level: :warning)

defmodule Analysis.GameSearchPostgresBenchmark do
  @moduledoc false

  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch
  alias Analysis.GameSearch.PostgresQuery
  alias Analysis.PositionQuery
  alias OpenChessLab.Repo

  @matching_white "Magnus Carlsen"
  @other_white "Other Player"

  @joined_first_page_sql """
  SELECT
    p.id,
    go.id,
    go.game_id,
    go.ply,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM positions AS p
  JOIN game_occurrences AS go
    ON go.position_id = p.id
  JOIN game_records AS gr
    ON gr.game_id = go.game_id
  WHERE gr.metadata @> $1::jsonb
  ORDER BY
    p.id,
    go.id,
    gr.id
  LIMIT $2::bigint
  """

  @joined_next_page_sql """
  SELECT
    p.id,
    go.id,
    go.game_id,
    go.ply,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM positions AS p
  JOIN game_occurrences AS go
    ON go.position_id = p.id
  JOIN game_records AS gr
    ON gr.game_id = go.game_id
  WHERE
    gr.metadata @> $1::jsonb
    AND (
      p.id,
      go.id,
      gr.id
    ) > (
      $2::bigint,
      $3::bigint,
      $4::bigint
    )
  ORDER BY
    p.id,
    go.id,
    gr.id
  LIMIT $5::bigint
  """

  def build(row_count, selectivity) do
    truncate()

    Repo.query!(
      """
      INSERT INTO positions (
        id,
        record
      )
      SELECT
        id,
        decode(
          lpad(
            to_hex(id),
            134,
            '0'
          ),
          'hex'
        )
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [row_count]
    )

    Repo.query!(
      """
      INSERT INTO games (
        id,
        fingerprint,
        content
      )
      SELECT
        id,
        decode(
          lpad(
            to_hex(id),
            64,
            '0'
          ),
          'hex'
        ),
        decode(
          lpad(
            to_hex(id),
            40,
            '0'
          ),
          'hex'
        )
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [row_count]
    )

    Repo.query!(
      """
      INSERT INTO game_occurrences (
        id,
        game_id,
        ply,
        position_id
      )
      SELECT
        id,
        id,
        0,
        id
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [row_count]
    )

    Repo.query!(
      """
      INSERT INTO game_records (
        id,
        record_id,
        game_id,
        fullmove_number,
        metadata
      )
      SELECT
        id,
        'record-' || id::text,
        id,
        1,
        jsonb_build_object(
          'white',
          CASE
            WHEN mod(
              id,
              $2::bigint
            ) = 0
              THEN $3::text
            ELSE $4::text
          END
        )
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [
        row_count,
        selectivity,
        @matching_white,
        @other_white
      ]
    )

    Repo.query!(
      """
      ANALYZE
        positions,
        games,
        game_occurrences,
        game_records
      """,
      []
    )

    :ok
  end

  def cleanup do
    truncate()
  end

  def handle_query(_event, _measurements, _metadata, parent) do
    send(
      parent,
      :game_search_benchmark_query
    )

    :ok
  end

  def application_first_page(page_size) do
    case GameSearch.page(
           PositionQuery.match_all(),
           record_query(),
           limit: page_size
         ) do
      {
        :ok,
        %GameSearch.Page{
          entries: matches
        }
      } ->
        matches

      {:error, reason} ->
        raise """
        first game-search page failed: #{inspect(reason)}
        """
    end
  end

  def application_cursor(page_size) do
    case GameSearch.page(
           PositionQuery.match_all(),
           record_query(),
           limit: page_size
         ) do
      {
        :ok,
        %GameSearch.Page{
          next: %GameSearch.Cursor{} = cursor
        }
      } ->
        cursor

      {
        :ok,
        %GameSearch.Page{
          next: nil
        }
      } ->
        raise """
        benchmark fixture does not contain enough matches
        for a second application page
        """

      {:error, reason} ->
        raise """
        first game-search page failed: #{inspect(reason)}
        """
    end
  end

  def application_second_page(%GameSearch.Cursor{} = cursor, page_size) do
    case GameSearch.page(
           PositionQuery.match_all(),
           record_query(),
           limit: page_size,
           cursor: cursor
         ) do
      {
        :ok,
        %GameSearch.Page{
          entries: matches
        }
      } ->
        matches

      {:error, reason} ->
        raise """
        second game-search page failed: #{inspect(reason)}
        """
    end
  end

  def application_first_sql_page(page_size) do
    {
      sql,
      parameters
    } =
      application_first_sql(page_size)

    Repo.query!(
      sql,
      parameters
    ).rows
  end

  def application_second_sql_page(%GameSearch.Cursor{} = cursor, page_size) do
    {
      sql,
      parameters
    } =
      application_second_sql(
        cursor,
        page_size
      )

    Repo.query!(
      sql,
      parameters
    ).rows
  end

  def joined_first_page(page_size) do
    Repo.query!(
      @joined_first_page_sql,
      [
        metadata(),
        page_size
      ]
    ).rows
  end

  def joined_keyset(page_size) do
    joined_first_page(page_size)
    |> List.last()
    |> case do
      [
        position_id,
        occurrence_id,
        _occurrence_game_id,
        _ply,
        record_row_id,
        _record_id,
        _record_game_id,
        _fullmove_number,
        _metadata
      ] ->
        {
          position_id,
          occurrence_id,
          record_row_id
        }

      nil ->
        raise """
        benchmark fixture did not produce a joined first page
        """
    end
  end

  def joined_second_page({position_id, occurrence_id, record_row_id}, page_size) do
    Repo.query!(
      @joined_next_page_sql,
      [
        metadata(),
        position_id,
        occurrence_id,
        record_row_id,
        page_size
      ]
    ).rows
  end

  def application_first_plan(page_size) do
    {
      sql,
      parameters
    } =
      application_first_sql(page_size)

    explain(
      sql,
      parameters
    )
  end

  def application_second_plan(%GameSearch.Cursor{} = cursor, page_size) do
    {
      sql,
      parameters
    } =
      application_second_sql(
        cursor,
        page_size
      )

    explain(
      sql,
      parameters
    )
  end

  def joined_first_plan(page_size) do
    explain(
      @joined_first_page_sql,
      [
        metadata(),
        page_size
      ]
    )
  end

  def joined_second_plan({position_id, occurrence_id, record_row_id}, page_size) do
    explain(
      @joined_next_page_sql,
      [
        metadata(),
        position_id,
        occurrence_id,
        record_row_id,
        page_size
      ]
    )
  end

  def query_count(fun) when is_function(fun, 0) do
    telemetry_prefix =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)

    event =
      telemetry_prefix ++
        [:query]

    handler_id = {
      __MODULE__,
      make_ref()
    }

    parent =
      self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_query/4,
        parent
      )

    try do
      result =
        fun.()

      {
        result,
        drain_query_count(0)
      }
    after
      :telemetry.detach(handler_id)

      drain_query_count(0)
    end
  end

  defp application_first_sql(page_size) do
    requested_rows =
      page_size + 1

    case PostgresQuery.compile_first(
           PositionQuery.match_all(),
           record_query(),
           requested_rows
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          sql,
          parameters
        }

      {:error, reason} ->
        raise """
        first game-search SQL compilation failed:
        #{inspect(reason)}
        """
    end
  end

  defp application_second_sql(%GameSearch.Cursor{} = cursor, page_size) do
    requested_rows =
      page_size + 1

    case PostgresQuery.compile_next(
           PositionQuery.match_all(),
           record_query(),
           cursor.maximum_position_id,
           cursor.maximum_occurrence_id,
           cursor.maximum_record_row_id,
           cursor.last_position_id,
           cursor.last_occurrence_id,
           cursor.last_record_row_id,
           requested_rows
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          sql,
          parameters
        }

      {:error, reason} ->
        raise """
        second game-search SQL compilation failed:
        #{inspect(reason)}
        """
    end
  end

  defp record_query do
    GameRecordQuery.metadata_contains(metadata())
  end

  defp metadata do
    %{
      "white" => @matching_white
    }
  end

  defp explain(sql, parameters) do
    Repo.query!(
      """
      EXPLAIN (
        ANALYZE,
        BUFFERS,
        COSTS TRUE,
        TIMING TRUE,
        SUMMARY TRUE
      )
      #{sql}
      """,
      parameters
    ).rows
    |> Enum.map_join(
      "\n",
      fn
        [line] ->
          line

        row ->
          inspect(row)
      end
    )
  end

  defp drain_query_count(count) do
    receive do
      :game_search_benchmark_query ->
        drain_query_count(count + 1)
    after
      0 ->
        count
    end
  end

  defp truncate do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database because this benchmark
    truncates the OpenChessLab PostgreSQL tables.

    Example:

        ecto://openchesslab:openchesslab@localhost/openchesslab_bench
    """

row_count =
  System.get_env(
    "GAME_SEARCH_BENCH_ROWS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "GAME_SEARCH_BENCH_SELECTIVITY",
    "10"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "GAME_SEARCH_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if row_count <= 0 do
  raise "GAME_SEARCH_BENCH_ROWS must be positive"
end

if selectivity <= 0 do
  raise "GAME_SEARCH_BENCH_SELECTIVITY must be positive"
end

if page_size <= 0 do
  raise "GAME_SEARCH_BENCH_PAGE_SIZE must be positive"
end

available_matches =
  div(
    row_count,
    selectivity
  )

if available_matches <= page_size do
  raise """
  benchmark fixture needs more than one result page.

  Available matches: #{available_matches}
  Page size: #{page_size}
  """
end

first_page_matches =
  min(
    page_size,
    available_matches
  )

remaining_matches =
  max(
    available_matches - page_size,
    0
  )

second_page_matches =
  min(
    page_size,
    remaining_matches
  )

first_application_sql_rows =
  min(
    page_size + 1,
    available_matches
  )

second_application_sql_rows =
  min(
    page_size + 1,
    remaining_matches
  )

try do
  IO.puts("""
  Building PostgreSQL game-search benchmark fixture...

  positions:   #{row_count}
  games:       #{row_count}
  occurrences: #{row_count}
  records:     #{row_count}
  selectivity: 1/#{selectivity}
  page size:   #{page_size}
  """)

  :ok =
    Benchmark.build(
      row_count,
      selectivity
    )

  application_cursor =
    Benchmark.application_cursor(page_size)

  joined_keyset =
    Benchmark.joined_keyset(page_size)

  {
    application_first_matches,
    application_first_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.application_first_page(page_size)
    end)

  {
    application_first_sql_rows_result,
    application_first_sql_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.application_first_sql_page(page_size)
    end)

  {
    joined_first_rows,
    joined_first_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.joined_first_page(page_size)
    end)

  {
    application_second_matches,
    application_second_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.application_second_page(
        application_cursor,
        page_size
      )
    end)

  {
    application_second_sql_rows_result,
    application_second_sql_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.application_second_sql_page(
        application_cursor,
        page_size
      )
    end)

  {
    joined_second_rows,
    joined_second_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.joined_second_page(
        joined_keyset,
        page_size
      )
    end)

  if length(application_first_matches) !=
       first_page_matches do
    raise """
    application first page expected #{first_page_matches} matches,
    got #{length(application_first_matches)}
    """
  end

  if length(application_first_sql_rows_result) !=
       first_application_sql_rows do
    raise """
    application first SQL expected #{first_application_sql_rows} rows,
    got #{length(application_first_sql_rows_result)}
    """
  end

  if length(joined_first_rows) !=
       first_page_matches do
    raise """
    joined first page expected #{first_page_matches} rows,
    got #{length(joined_first_rows)}
    """
  end

  if length(application_second_matches) !=
       second_page_matches do
    raise """
    application second page expected #{second_page_matches} matches,
    got #{length(application_second_matches)}
    """
  end

  if length(application_second_sql_rows_result) !=
       second_application_sql_rows do
    raise """
    application second SQL expected #{second_application_sql_rows} rows,
    got #{length(application_second_sql_rows_result)}
    """
  end

  if length(joined_second_rows) !=
       second_page_matches do
    raise """
    joined second page expected #{second_page_matches} rows,
    got #{length(joined_second_rows)}
    """
  end

  IO.puts("""
  PostgreSQL game-search benchmark

  rows per relation: #{row_count}
  selectivity:       1/#{selectivity}
  result page:       #{page_size}

  First page:
    expected matches:     #{first_page_matches}
    application queries:  #{application_first_query_count}
    application SQL:      #{application_first_sql_query_count}
    joined baseline:      #{joined_first_query_count}

  Second page:
    expected matches:     #{second_page_matches}
    application queries:  #{application_second_query_count}
    application SQL:      #{application_second_sql_query_count}
    joined baseline:      #{joined_second_query_count}

  Application first-page plan:
  #{Benchmark.application_first_plan(page_size)}

  Joined first-page baseline plan:
  #{Benchmark.joined_first_plan(page_size)}

  Application second-page plan:
  #{Benchmark.application_second_plan(application_cursor, page_size)}

  Joined second-page baseline plan:
  #{Benchmark.joined_second_plan(joined_keyset, page_size)}
  """)

  Benchee.run(
    %{
      "game search: first page application" => fn ->
        matches =
          Benchmark.application_first_page(page_size)

        if length(matches) !=
             first_page_matches do
          raise """
          expected #{first_page_matches} matches,
          got #{length(matches)}
          """
        end

        matches
      end,
      "game search: first page application SQL" => fn ->
        rows =
          Benchmark.application_first_sql_page(page_size)

        if length(rows) !=
             first_application_sql_rows do
          raise """
          expected #{first_application_sql_rows} rows,
          got #{length(rows)}
          """
        end

        rows
      end,
      "game search: first page joined baseline" => fn ->
        rows =
          Benchmark.joined_first_page(page_size)

        if length(rows) !=
             first_page_matches do
          raise """
          expected #{first_page_matches} rows,
          got #{length(rows)}
          """
        end

        rows
      end,
      "game search: second page application" => fn ->
        matches =
          Benchmark.application_second_page(
            application_cursor,
            page_size
          )

        if length(matches) !=
             second_page_matches do
          raise """
          expected #{second_page_matches} matches,
          got #{length(matches)}
          """
        end

        matches
      end,
      "game search: second page application SQL" => fn ->
        rows =
          Benchmark.application_second_sql_page(
            application_cursor,
            page_size
          )

        if length(rows) !=
             second_application_sql_rows do
          raise """
          expected #{second_application_sql_rows} rows,
          got #{length(rows)}
          """
        end

        rows
      end,
      "game search: second page joined baseline" => fn ->
        rows =
          Benchmark.joined_second_page(
            joined_keyset,
            page_size
          )

        if length(rows) !=
             second_page_matches do
          raise """
          expected #{second_page_matches} rows,
          got #{length(rows)}
          """
        end

        rows
      end
    },
    warmup: 1,
    time: 3,
    parallel: 1
  )
after
  Benchmark.cleanup()
end
