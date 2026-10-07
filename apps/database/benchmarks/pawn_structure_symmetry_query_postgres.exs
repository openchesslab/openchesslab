alias OpenChessLab.Database.PawnStructureSymmetryQueryPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureSymmetryQueryPostgresBenchmark do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "openchesslab_pawn_structure_symmetry_benchmark"
  @index "#{@table}_paging_index"

  @target_parameters [
    1001,
    2001,
    1002,
    2002,
    1003,
    2003,
    1004,
    2004
  ]

  @or_first_page_sql """
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
    (
      (
        p.white_pawns = $1::bigint
        AND p.black_pawns = $2::bigint
      )
      OR
      (
        p.white_pawns = $3::bigint
        AND p.black_pawns = $4::bigint
      )
      OR
      (
        p.white_pawns = $5::bigint
        AND p.black_pawns = $6::bigint
      )
      OR
      (
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
      )
    )
  ORDER BY
    p.id
  LIMIT $9::bigint
  """

  @or_next_page_sql """
  SELECT
    $9::bigint AS maximum_position_id,
    p.id
  FROM #{@table} AS p
  WHERE
    p.id > $10::bigint
    AND p.id <= $9::bigint
    AND (
      (
        p.white_pawns = $1::bigint
        AND p.black_pawns = $2::bigint
      )
      OR
      (
        p.white_pawns = $3::bigint
        AND p.black_pawns = $4::bigint
      )
      OR
      (
        p.white_pawns = $5::bigint
        AND p.black_pawns = $6::bigint
      )
      OR
      (
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
      )
    )
  ORDER BY
    p.id
  LIMIT $11::bigint
  """

  @union_first_page_sql """
  SELECT
    COALESCE(
      (
        SELECT max(id)
        FROM #{@table}
      ),
      0
    )::bigint AS maximum_position_id,
    matches.id
  FROM (
    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $1::bigint
        AND p.black_pawns = $2::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $3::bigint
        AND p.black_pawns = $4::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $5::bigint
        AND p.black_pawns = $6::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
      ORDER BY
        p.id
    )
  ) AS matches
  ORDER BY
    matches.id
  LIMIT $9::bigint
  """

  @union_next_page_sql """
  SELECT
    $9::bigint AS maximum_position_id,
    matches.id
  FROM (
    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $1::bigint
        AND p.black_pawns = $2::bigint
        AND p.id > $10::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $3::bigint
        AND p.black_pawns = $4::bigint
        AND p.id > $10::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $5::bigint
        AND p.black_pawns = $6::bigint
        AND p.id > $10::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@table} AS p
      WHERE
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
        AND p.id > $10::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )
  ) AS matches
  ORDER BY
    matches.id
  LIMIT $11::bigint
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
            THEN
              CASE mod(
                id / $2::bigint,
                4
              )
                WHEN 0 THEN $3::bigint
                WHEN 1 THEN $5::bigint
                WHEN 2 THEN $7::bigint
                WHEN 3 THEN $9::bigint
              END
          ELSE id
        END,
        CASE
          WHEN mod(
            id,
            $2::bigint
          ) = 0
            THEN
              CASE mod(
                id / $2::bigint,
                4
              )
                WHEN 0 THEN $4::bigint
                WHEN 1 THEN $6::bigint
                WHEN 2 THEN $8::bigint
                WHEN 3 THEN $10::bigint
              END
          ELSE -id
        END
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [
        row_count,
        selectivity
        | @target_parameters
      ]
    )

    setup_query!("""
    CREATE INDEX #{@index}
    ON #{@table} (
      white_pawns,
      black_pawns,
      id
    )
    """)

    setup_query!("ANALYZE #{@table}")

    %{
      row_count: row_count,
      table_size: relation_size(@table),
      index_size: relation_size(@index),
      total_size: total_relation_size(@table)
    }
  end

  def benchmark(posting_count, selectivity, page_size, row_count) do
    or_first_page =
      first_page(
        :or,
        page_size
      )

    union_first_page =
      first_page(
        :union_all,
        page_size
      )

    if or_first_page !=
         union_first_page do
      raise """
      OR and UNION ALL returned different first pages.

      OR:
      #{inspect(or_first_page)}

      UNION ALL:
      #{inspect(union_first_page)}
      """
    end

    last_position_id =
      or_first_page
      |> Map.fetch!(:position_ids)
      |> List.last()

    expected_first_page_size =
      min(
        posting_count,
        page_size
      )

    expected_second_page_size =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(page_size)

    validate_page!(
      or_first_page,
      row_count,
      expected_first_page_size,
      selectivity
    )

    or_second_page =
      next_page(
        :or,
        row_count,
        last_position_id,
        page_size
      )

    union_second_page =
      next_page(
        :union_all,
        row_count,
        last_position_id,
        page_size
      )

    if or_second_page !=
         union_second_page do
      raise """
      OR and UNION ALL returned different second pages.

      OR:
      #{inspect(or_second_page)}

      UNION ALL:
      #{inspect(union_second_page)}
      """
    end

    validate_page!(
      or_second_page,
      row_count,
      expected_second_page_size,
      selectivity
    )

    IO.puts("""
    Current OR query

    First-page plan:
    #{first_page_plan(:or,
    page_size)}

    Second-page plan:
    #{next_page_plan(:or,
    row_count,
    last_position_id,
    page_size)}

    Ordered UNION ALL query

    First-page plan:
    #{first_page_plan(:union_all,
    page_size)}

    Second-page plan:
    #{next_page_plan(:union_all,
    row_count,
    last_position_id,
    page_size)}
    """)

    Benchee.run(
      %{
        "current OR: first page" => fn ->
          result =
            first_page(
              :or,
              page_size
            )

          validate_page!(
            result,
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "current OR: second page" => fn ->
          result =
            next_page(
              :or,
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
        "ordered UNION ALL: first page" => fn ->
          result =
            first_page(
              :union_all,
              page_size
            )

          validate_page!(
            result,
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "ordered UNION ALL: second page" => fn ->
          result =
            next_page(
              :union_all,
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
        end
      },
      warmup: 1,
      time: 3,
      parallel: 1
    )
  end

  def cleanup do
    drop_table()
  end

  def first_page(shape, page_size) do
    shape
    |> first_page_sql()
    |> query_page(
      @target_parameters ++
        [
          page_size
        ]
    )
  end

  def next_page(shape, maximum_position_id, last_position_id, page_size) do
    shape
    |> next_page_sql()
    |> query_page(
      @target_parameters ++
        [
          maximum_position_id,
          last_position_id,
          page_size
        ]
    )
  end

  def first_page_plan(shape, page_size) do
    explain(
      first_page_sql(shape),
      @target_parameters ++
        [
          page_size
        ]
    )
  end

  def next_page_plan(shape, maximum_position_id, last_position_id, page_size) do
    explain(
      next_page_sql(shape),
      @target_parameters ++
        [
          maximum_position_id,
          last_position_id,
          page_size
        ]
    )
  end

  defp first_page_sql(:or) do
    @or_first_page_sql
  end

  defp first_page_sql(:union_all) do
    @union_first_page_sql
  end

  defp next_page_sql(:or) do
    @or_next_page_sql
  end

  defp next_page_sql(:union_all) do
    @union_next_page_sql
  end

  defp query_page(sql, parameters) do
    rows =
      SQL.query!(
        Repo,
        sql,
        parameters
      ).rows

    page_from_rows(rows)
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

    if result.position_ids !=
         Enum.sort(result.position_ids) do
      raise """
      page is not ordered by position ID
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
      page contains a position outside the symmetry fixture
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
    "PAWN_SYMMETRY_BENCH_POSTINGS",
    "1000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_SYMMETRY_BENCH_SELECTIVITY",
    "1000"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_SYMMETRY_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_SYMMETRY_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_SYMMETRY_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_SYMMETRY_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count < page_size * 2 do
  raise """
  PAWN_SYMMETRY_BENCH_POSTINGS must be at least twice
  PAWN_SYMMETRY_BENCH_PAGE_SIZE so the benchmark has a full
  second page.
  """
end

try do
  IO.puts("""
  Building PostgreSQL pawn-structure symmetry benchmark fixture...

  symmetry matches: #{posting_count}
  selectivity:      1/#{selectivity}
  rows:             #{posting_count * selectivity}
  symmetry keys:    4
  page size:        #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  PostgreSQL pawn-structure symmetry query benchmark

  rows:       #{fixture.row_count}
  table size: #{fixture.table_size} bytes
  index size: #{fixture.index_size} bytes
  total size: #{fixture.total_size} bytes

  Comparing the current four-way OR predicate with four ordered
  equality scans combined using UNION ALL.
  """)

  Benchmark.benchmark(
    posting_count,
    selectivity,
    page_size,
    fixture.row_count
  )
after
  Benchmark.cleanup()
end
