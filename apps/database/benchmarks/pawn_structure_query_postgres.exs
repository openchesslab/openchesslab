alias OpenChessLab.Database.PawnStructureQueryPostgresBenchmark, as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureQueryPostgresBenchmark do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "openchesslab_pawn_structure_benchmark"

  @filter_index "#{@table}_filter_index"
  @paging_index "#{@table}_paging_index"

  @selected_white_pawns 65_280
  @selected_black_pawns 71_776_119_061_217_280

  @first_result_sql """
  SELECT
    COALESCE(
      (
        SELECT max(id)
        FROM #{@table}
      ),
      0
    )::bigint AS maximum_position_id,
    p.id
  FROM #{@table} AS p
  WHERE
    p.white_pawns = $1::bigint
    AND p.black_pawns = $2::bigint
  ORDER BY
    p.id
  LIMIT 1
  """

  @first_page_sql """
  SELECT
    COALESCE(
      (
        SELECT max(id)
        FROM #{@table}
      ),
      0
    )::bigint AS maximum_position_id,
    p.id
  FROM #{@table} AS p
  WHERE
    p.white_pawns = $1::bigint
    AND p.black_pawns = $2::bigint
  ORDER BY
    p.id
  LIMIT $3::bigint
  """

  @next_page_sql """
  SELECT
    $3::bigint AS maximum_position_id,
    p.id
  FROM #{@table} AS p
  WHERE
    p.id > $4::bigint
    AND p.id <= $3::bigint
    AND p.white_pawns = $1::bigint
    AND p.black_pawns = $2::bigint
  ORDER BY
    p.id
  LIMIT $5::bigint
  """

  @cardinality_sql """
  SELECT count(*)
  FROM #{@table} AS p
  WHERE
    p.white_pawns = $1::bigint
    AND p.black_pawns = $2::bigint
  """

  def build(posting_count, selectivity) do
    row_count =
      posting_count *
        selectivity

    drop_table()

    setup_query!("""
    CREATE TABLE #{@table} (
      id bigint PRIMARY KEY,
      white_pawns bigint NOT NULL,
      black_pawns bigint NOT NULL
    )
    """)

    setup_query!(
      """
      INSERT INTO #{@table} (
        id,
        white_pawns,
        black_pawns
      )
      SELECT
        id,
        CASE
          WHEN mod(
            id,
            $2::bigint
          ) = 0
            THEN $3::bigint
          ELSE id
        END,
        CASE
          WHEN mod(
            id,
            $2::bigint
          ) = 0
            THEN $4::bigint
          ELSE -id
        END
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [
        row_count,
        selectivity,
        @selected_white_pawns,
        @selected_black_pawns
      ]
    )

    setup_query!("ANALYZE #{@table}")

    %{
      row_count: row_count,
      table_size: relation_size(@table),
      total_size: total_relation_size(@table)
    }
  end

  def benchmark_variant(variant, posting_count, selectivity, page_size, row_count) do
    index =
      create_index(variant)

    setup_query!("ANALYZE #{@table}")

    first_page =
      first_page(page_size)

    last_position_id =
      first_page
      |> Map.fetch!(:position_ids)
      |> List.last()

    expected_second_page_size =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(page_size)

    IO.puts("""
    #{variant_label(variant)}

    index size: #{relation_size(index)} bytes

    First-page plan:
    #{first_page_plan(page_size)}

    Second-page plan:
    #{next_page_plan(row_count,
    last_position_id,
    page_size)}

    Cardinality plan:
    #{cardinality_plan()}
    """)

    Benchee.run(
      %{
        "#{variant_label(variant)}: first result" => fn ->
          case first_result() do
            {
              ^row_count,
              position_id
            }
            when rem(position_id, selectivity) == 0 ->
              :ok

            result ->
              raise """
              unexpected first result:
              #{inspect(result)}
              """
          end
        end,
        "#{variant_label(variant)}: first page" => fn ->
          result =
            first_page(page_size)

          validate_page!(
            result,
            row_count,
            min(
              posting_count,
              page_size
            ),
            selectivity
          )
        end,
        "#{variant_label(variant)}: second page" => fn ->
          result =
            next_page(
              row_count,
              last_position_id,
              page_size
            )

          validate_page!(
            result,
            row_count,
            expected_second_page_size,
            selectivity
          )
        end,
        "#{variant_label(variant)}: cardinality" => fn ->
          case cardinality() do
            ^posting_count ->
              :ok

            actual ->
              raise """
              expected cardinality #{posting_count},
              got #{actual}
              """
          end
        end
      },
      warmup: 1,
      time: 3,
      parallel: 1
    )

    drop_index(index)

    :ok
  end

  def cleanup do
    drop_table()
  end

  def first_result do
    case SQL.query!(
           Repo,
           @first_result_sql,
           selected_parameters()
         ).rows do
      [
        [
          maximum_position_id,
          position_id
        ]
      ] ->
        {
          maximum_position_id,
          position_id
        }

      rows ->
        raise """
        unexpected first-result rows:
        #{inspect(rows)}
        """
    end
  end

  def first_page(page_size) do
    rows =
      SQL.query!(
        Repo,
        @first_page_sql,
        selected_parameters() ++
          [
            page_size
          ]
      ).rows

    page_from_rows(rows)
  end

  def next_page(maximum_position_id, last_position_id, page_size) do
    rows =
      SQL.query!(
        Repo,
        @next_page_sql,
        selected_parameters() ++
          [
            maximum_position_id,
            last_position_id,
            page_size
          ]
      ).rows

    page_from_rows(rows)
  end

  def cardinality do
    case SQL.query!(
           Repo,
           @cardinality_sql,
           selected_parameters()
         ).rows do
      [
        [
          count
        ]
      ] ->
        count

      rows ->
        raise """
        unexpected cardinality rows:
        #{inspect(rows)}
        """
    end
  end

  def first_page_plan(page_size) do
    explain(
      @first_page_sql,
      selected_parameters() ++
        [
          page_size
        ]
    )
  end

  def next_page_plan(maximum_position_id, last_position_id, page_size) do
    explain(
      @next_page_sql,
      selected_parameters() ++
        [
          maximum_position_id,
          last_position_id,
          page_size
        ]
    )
  end

  def cardinality_plan do
    explain(
      @cardinality_sql,
      selected_parameters()
    )
  end

  defp create_index(:filter_only) do
    setup_query!("""
    CREATE INDEX #{@filter_index}
    ON #{@table} (
      white_pawns,
      black_pawns
    )
    """)

    @filter_index
  end

  defp create_index(:paging) do
    setup_query!("""
    CREATE INDEX #{@paging_index}
    ON #{@table} (
      white_pawns,
      black_pawns,
      id
    )
    """)

    @paging_index
  end

  defp drop_index(index) do
    setup_query!("DROP INDEX IF EXISTS #{index}")
  end

  defp variant_label(:filter_only) do
    "filter index (white_pawns, black_pawns)"
  end

  defp variant_label(:paging) do
    "paging index (white_pawns, black_pawns, id)"
  end

  defp selected_parameters do
    [
      @selected_white_pawns,
      @selected_black_pawns
    ]
  end

  defp page_from_rows([]) do
    %{
      maximum_position_id: nil,
      position_ids: []
    }
  end

  defp page_from_rows(rows) do
    maximum_position_id =
      rows
      |> hd()
      |> hd()

    position_ids =
      Enum.map(
        rows,
        fn
          [
            ^maximum_position_id,
            position_id
          ] ->
            position_id

          row ->
            raise """
            inconsistent page row:
            #{inspect(row)}
            """
        end
      )

    %{
      maximum_position_id: maximum_position_id,
      position_ids: position_ids
    }
  end

  defp validate_page!(result, expected_maximum_position_id, expected_count, selectivity) do
    if result.maximum_position_id !=
         expected_maximum_position_id do
      raise """
      expected maximum position ID #{expected_maximum_position_id},
      got #{inspect(result.maximum_position_id)}
      """
    end

    if length(result.position_ids) !=
         expected_count do
      raise """
      expected #{expected_count} positions,
      got #{length(result.position_ids)}
      """
    end

    if !Enum.all?(
         result.position_ids,
         fn position_id ->
           rem(
             position_id,
             selectivity
           ) == 0
         end
       ) do
      raise """
      page contains a position outside the selected pawn structure
      """
    end

    result
  end

  defp explain(sql, parameters) do
    Repo
    |> SQL.query!(
      """
      EXPLAIN (
        ANALYZE TRUE,
        BUFFERS TRUE,
        COSTS TRUE
      )
      #{sql}
      """,
      parameters
    )
    |> Map.fetch!(:rows)
    |> Enum.map_join(
      "\n",
      fn
        [
          line
        ] ->
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
           SELECT pg_relation_size(
             to_regclass($1::text)
           )
           """,
           [
             relation
           ]
         ).rows do
      [
        [
          size
        ]
      ] ->
        size
    end
  end

  defp total_relation_size(relation) do
    case SQL.query!(
           Repo,
           """
           SELECT pg_total_relation_size(
             to_regclass($1::text)
           )
           """,
           [
             relation
           ]
         ).rows do
      [
        [
          size
        ]
      ] ->
        size
    end
  end

  defp setup_query!(sql, parameters \\ []) do
    SQL.query!(
      Repo,
      sql,
      parameters,
      timeout: :infinity
    )
  end

  defp drop_table do
    setup_query!("DROP TABLE IF EXISTS #{@table}")
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database.

    Example:

        ecto://openchesslab:openchesslab@localhost/openchesslab_bench
    """

posting_count =
  System.get_env(
    "PAWN_STRUCTURE_BENCH_POSTINGS",
    "100000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_STRUCTURE_BENCH_SELECTIVITY",
    "10"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_STRUCTURE_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_STRUCTURE_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_STRUCTURE_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_STRUCTURE_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count < page_size do
  raise """
  PAWN_STRUCTURE_BENCH_POSTINGS must be at least
  PAWN_STRUCTURE_BENCH_PAGE_SIZE
  """
end

try do
  IO.puts("""
  Building PostgreSQL pawn-structure benchmark fixture...

  postings:    #{posting_count}
  selectivity: 1/#{selectivity}
  rows:        #{posting_count * selectivity}
  page size:   #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  PostgreSQL pawn-structure query benchmark

  rows:       #{fixture.row_count}
  table size: #{fixture.table_size} bytes
  total size: #{fixture.total_size} bytes

  Comparing the current filter-only index with an index whose final
  column matches PositionStore's keyset paging order.
  """)

  Benchmark.benchmark_variant(
    :filter_only,
    posting_count,
    selectivity,
    page_size,
    fixture.row_count
  )

  Benchmark.benchmark_variant(
    :paging,
    posting_count,
    selectivity,
    page_size,
    fixture.row_count
  )
after
  Benchmark.cleanup()
end
