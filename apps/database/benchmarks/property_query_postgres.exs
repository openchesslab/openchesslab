alias OpenChessLab.Database.PropertyQueryPostgresBenchmark, as: Benchmark

defmodule OpenChessLab.Database.PropertyQueryPostgresBenchmark do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "openchesslab_property_query_benchmark"
  @index "#{@table}_properties_gin"

  @selected_property <<1>>

  @first_result_sql """
  SELECT id
  FROM #{@table}
  WHERE properties @> ARRAY[$1::bytea]::bytea[]
  LIMIT 1
  """

  @first_page_sql """
  SELECT id
  FROM #{@table}
  WHERE properties @> ARRAY[$1::bytea]::bytea[]
  LIMIT $2::bigint
  """

  @cardinality_sql """
  SELECT count(*)
  FROM #{@table}
  WHERE properties @> ARRAY[$1::bytea]::bytea[]
  """

  def start_repo(database_url) do
    Repo.start_link(
      url: database_url,
      pool_size: 1,
      log: false
    )
  end

  def build(posting_count, selectivity) do
    row_count =
      posting_count *
        selectivity

    drop_table()

    SQL.query!(
      Repo,
      """
      CREATE TABLE #{@table} (
        id bigint PRIMARY KEY,
        properties bytea[] NOT NULL
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      INSERT INTO #{@table} (id, properties)
      SELECT
        id,
        CASE
          WHEN mod(id, $2::bigint) = 0
            THEN ARRAY[$3::bytea]::bytea[]
          ELSE ARRAY[]::bytea[]
        END
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [
        row_count,
        selectivity,
        @selected_property
      ]
    )

    SQL.query!(
      Repo,
      """
      CREATE INDEX #{@index}
      ON #{@table}
      USING gin (properties)
      """,
      []
    )

    SQL.query!(
      Repo,
      "ANALYZE #{@table}",
      []
    )

    %{
      row_count: row_count,
      table_size: relation_size(@table),
      index_size: relation_size(@index),
      total_size: total_relation_size(@table)
    }
  end

  def cleanup do
    drop_table()
  end

  def first_result do
    case SQL.query!(
           Repo,
           @first_result_sql,
           [@selected_property]
         ).rows do
      [[position_id]] ->
        position_id

      rows ->
        raise "unexpected first-result rows: #{inspect(rows)}"
    end
  end

  def first_page(page_size) do
    Repo
    |> SQL.query!(
      @first_page_sql,
      [
        @selected_property,
        page_size
      ]
    )
    |> Map.fetch!(:rows)
    |> Enum.map(fn
      [position_id] ->
        position_id

      row ->
        raise "unexpected first-page row: #{inspect(row)}"
    end)
  end

  def cardinality do
    case SQL.query!(
           Repo,
           @cardinality_sql,
           [@selected_property]
         ).rows do
      [[count]] ->
        count

      rows ->
        raise "unexpected cardinality rows: #{inspect(rows)}"
    end
  end

  def first_page_plan(page_size) do
    explain(
      @first_page_sql,
      [
        @selected_property,
        page_size
      ]
    )
  end

  def cardinality_plan do
    explain(
      @cardinality_sql,
      [@selected_property]
    )
  end

  defp explain(sql, parameters) do
    Repo
    |> SQL.query!(
      "EXPLAIN (COSTS TRUE)\n#{sql}",
      parameters
    )
    |> Map.fetch!(:rows)
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

  defp relation_size(relation) do
    case SQL.query!(
           Repo,
           """
           SELECT pg_relation_size(to_regclass($1::text))
           """,
           [relation]
         ).rows do
      [[size]] ->
        size
    end
  end

  defp total_relation_size(relation) do
    case SQL.query!(
           Repo,
           """
           SELECT pg_total_relation_size(to_regclass($1::text))
           """,
           [relation]
         ).rows do
      [[size]] ->
        size
    end
  end

  defp drop_table do
    SQL.query!(
      Repo,
      "DROP TABLE IF EXISTS #{@table}",
      []
    )
  end
end

database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Example:

        ecto://postgres:postgres@localhost/openchesslab_bench
    """

posting_count =
  System.get_env(
    "POSTGRES_BENCH_POSTINGS",
    "100000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "POSTGRES_BENCH_SELECTIVITY",
    "10"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "POSTGRES_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise "POSTGRES_BENCH_POSTINGS must be positive"
end

if selectivity <= 0 do
  raise "POSTGRES_BENCH_SELECTIVITY must be positive"
end

if page_size <= 0 do
  raise "POSTGRES_BENCH_PAGE_SIZE must be positive"
end

{:ok, repo_pid} =
  Benchmark.start_repo(database_url)

try do
  IO.puts("""
  Building PostgreSQL property-query benchmark fixture...

  postings:    #{posting_count}
  selectivity: 1/#{selectivity}
  rows:        #{posting_count * selectivity}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  expected_page_size =
    min(
      posting_count,
      page_size
    )

  IO.puts("""
  PostgreSQL property-query benchmark

  postings:    #{posting_count}
  rows:        #{fixture.row_count}
  page size:   #{page_size}
  table size:  #{fixture.table_size} bytes
  GIN size:    #{fixture.index_size} bytes
  total size:  #{fixture.total_size} bytes

  First-page plan:
  #{Benchmark.first_page_plan(page_size)}

  Cardinality plan:
  #{Benchmark.cardinality_plan()}
  """)

  Benchee.run(
    %{
      "property query: first result" => fn ->
        position_id =
          Benchmark.first_result()

        if rem(
             position_id,
             selectivity
           ) != 0 do
          raise "unexpected position ID: #{position_id}"
        end

        :ok
      end,
      "property query: first page" => fn ->
        position_ids =
          Benchmark.first_page(page_size)

        if length(position_ids) !=
             expected_page_size do
          raise """
          expected #{expected_page_size} positions, got #{length(position_ids)}
          """
        end

        if !Enum.all?(
             position_ids,
             fn position_id ->
               rem(
                 position_id,
                 selectivity
               ) == 0
             end
           ) do
          raise "first page contains an unexpected position ID"
        end

        position_ids
      end,
      "property cardinality" => fn ->
        case Benchmark.cardinality() do
          ^posting_count ->
            :ok

          actual ->
            raise """
            expected cardinality #{posting_count}, got #{actual}
            """
        end
      end
    },
    warmup: 1,
    time: 3,
    parallel: 1
  )
after
  Benchmark.cleanup()
  GenServer.stop(repo_pid)
end
