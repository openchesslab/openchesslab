alias Analysis.GameSearchPostgresBenchmark, as: Benchmark

Logger.configure(level: :info)

defmodule Analysis.GameSearchPostgresBenchmark do
  @moduledoc false

  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch
  alias Analysis.PositionQuery
  alias OpenChessLab.Repo

  @matching_white "Magnus Carlsen"
  @other_white "Other Player"

  @joined_result_page_sql """
  SELECT
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata,
    go.id,
    go.game_id,
    go.ply,
    go.position_id
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

  def application_result_page(page_size) do
    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => @matching_white
      })

    case GameSearch.page(
           PositionQuery.match_all(),
           record_query,
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
        game search failed: #{inspect(reason)}
        """
    end
  end

  def joined_result_page(page_size) do
    Repo.query!(
      @joined_result_page_sql,
      [
        %{
          "white" => @matching_white
        },
        page_size
      ]
    ).rows
  end

  def joined_plan(page_size) do
    Repo.query!(
      """
      EXPLAIN (COSTS TRUE)
      #{@joined_result_page_sql}
      """,
      [
        %{
          "white" => @matching_white
        },
        page_size
      ]
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

expected_matches =
  min(
    page_size,
    available_matches
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

  {
    application_matches,
    application_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.application_result_page(page_size)
    end)

  {
    joined_matches,
    joined_query_count
  } =
    Benchmark.query_count(fn ->
      Benchmark.joined_result_page(page_size)
    end)

  if length(application_matches) !=
       expected_matches do
    raise """
    application flow expected #{expected_matches} matches,
    got #{length(application_matches)}
    """
  end

  if length(joined_matches) !=
       expected_matches do
    raise """
    joined SQL expected #{expected_matches} matches,
    got #{length(joined_matches)}
    """
  end

  IO.puts("""
  PostgreSQL game-search benchmark

  rows per relation: #{row_count}
  selectivity:       1/#{selectivity}
  result page:       #{page_size}
  expected matches:  #{expected_matches}

  SQL queries for one result page:
    application flow:    #{application_query_count}
    joined SQL baseline: #{joined_query_count}

  Joined SQL plan:
  #{Benchmark.joined_plan(page_size)}
  """)

  Benchee.run(
    %{
      "game search: application flow" => fn ->
        matches =
          Benchmark.application_result_page(page_size)

        if length(matches) !=
             expected_matches do
          raise """
          expected #{expected_matches} matches,
          got #{length(matches)}
          """
        end

        matches
      end,
      "game search: joined SQL baseline" => fn ->
        rows =
          Benchmark.joined_result_page(page_size)

        if length(rows) !=
             expected_matches do
          raise """
          expected #{expected_matches} matches,
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
