alias OpenChessLab.Database.PawnStructureSymmetryQueryPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureSymmetryQueryPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.PawnStructure
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "openchesslab_pawn_structure_symmetry_benchmark"
  @index "#{@table}_paging_index"

  # One white pawn on b4 and one black pawn on f6.
  #
  # This structure has four distinct supported symmetries:
  #
  #   exact
  #   color reversed
  #   file reflected
  #   color reversed + file reflected
  #
  # The values are ordinary bitboards and deliberately stay below
  # PostgreSQL's signed-bigint high bit.
  @source_structure %PawnStructure{
    white: 33_554_432,
    black: 35_184_372_088_832
  }

  def build(posting_count, selectivity) do
    row_count =
      posting_count *
        selectivity

    target_parameters =
      encoded_symmetry_parameters()

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
        | target_parameters
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
    generic_query =
      generic_or_query()

    optimized_query =
      PositionQuery.pawn_structure_symmetries(@source_structure)

    {
      generic_first_sql,
      generic_first_parameters
    } =
      compile_first!(
        generic_query,
        page_size
      )

    {
      optimized_first_sql,
      optimized_first_parameters
    } =
      compile_first!(
        optimized_query,
        page_size
      )

    validate_first_page_shapes!(
      generic_first_sql,
      optimized_first_sql
    )

    generic_first_page =
      query_page(
        generic_first_sql,
        generic_first_parameters
      )

    optimized_first_page =
      query_page(
        optimized_first_sql,
        optimized_first_parameters
      )

    assert_same_page!(
      "first",
      generic_first_page,
      optimized_first_page
    )

    expected_first_page_size =
      min(
        posting_count,
        page_size
      )

    validate_page!(
      generic_first_page,
      row_count,
      expected_first_page_size,
      selectivity
    )

    last_position_id =
      generic_first_page
      |> Map.fetch!(:position_ids)
      |> List.last()

    {
      generic_next_sql,
      generic_next_parameters
    } =
      compile_next!(
        generic_query,
        row_count,
        last_position_id,
        page_size
      )

    {
      optimized_next_sql,
      optimized_next_parameters
    } =
      compile_next!(
        optimized_query,
        row_count,
        last_position_id,
        page_size
      )

    validate_next_page_shapes!(
      generic_next_sql,
      optimized_next_sql
    )

    generic_second_page =
      query_page(
        generic_next_sql,
        generic_next_parameters
      )

    optimized_second_page =
      query_page(
        optimized_next_sql,
        optimized_next_parameters
      )

    assert_same_page!(
      "second",
      generic_second_page,
      optimized_second_page
    )

    expected_second_page_size =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(page_size)

    validate_page!(
      generic_second_page,
      row_count,
      expected_second_page_size,
      selectivity
    )

    IO.puts("""
    Generic OR compiler route

    First-page plan:
    #{explain(generic_first_sql,
    generic_first_parameters)}

    Second-page plan:
    #{explain(generic_next_sql,
    generic_next_parameters)}

    Specialized symmetry compiler route

    First-page plan:
    #{explain(optimized_first_sql,
    optimized_first_parameters)}

    Second-page plan:
    #{explain(optimized_next_sql,
    optimized_next_parameters)}
    """)

    Benchee.run(
      %{
        "generic OR compiler: first page" => fn ->
          generic_first_sql
          |> query_page(generic_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "generic OR compiler: second page" => fn ->
          generic_next_sql
          |> query_page(generic_next_parameters)
          |> validate_page!(
            row_count,
            expected_second_page_size,
            selectivity
          )
        end,
        "specialized symmetry compiler: first page" => fn ->
          optimized_first_sql
          |> query_page(optimized_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "specialized symmetry compiler: second page" => fn ->
          optimized_next_sql
          |> query_page(optimized_next_parameters)
          |> validate_page!(
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

  defp generic_or_query do
    @source_structure
    |> PawnStructure.symmetries()
    |> Enum.map(&PositionQuery.pawn_structure/1)
    |> PositionQuery.any()
  end

  defp encoded_symmetry_parameters do
    structures =
      PawnStructure.symmetries(@source_structure)

    if length(structures) != 4 do
      raise """
      benchmark source structure must have four distinct symmetries,
      got #{length(structures)}
      """
    end

    Enum.flat_map(
      structures,
      fn structure ->
        case PositionPawnStructureCodec.encode(structure) do
          {:ok,
           {
             white_pawns,
             black_pawns
           }} ->
            [
              white_pawns,
              black_pawns
            ]

          {:error, reason} ->
            raise """
            could not encode benchmark pawn structure:

            #{inspect(reason)}
            """
        end
      end
    )
  end

  defp compile_first!(query, page_size) do
    case PostgresPage.compile_first(
           query,
           page_size
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          benchmark_relation(sql),
          parameters
        }

      {:error, reason} ->
        raise """
        could not compile first page:

        #{inspect(reason)}
        """
    end
  end

  defp compile_next!(query, maximum_position_id, last_position_id, page_size) do
    case PostgresPage.compile_next(
           query,
           maximum_position_id,
           last_position_id,
           page_size
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          benchmark_relation(sql),
          parameters
        }

      {:error, reason} ->
        raise """
        could not compile next page:

        #{inspect(reason)}
        """
    end
  end

  # The production compiler deliberately targets the canonical
  # `positions` relation. The benchmark uses a compact synthetic
  # relation with the same indexed columns so a 10M-row fixture does
  # not also need to materialize 67-byte canonical position records
  # and their unique index.
  #
  # Only the relation identifier is substituted. The predicate,
  # UNION ALL branches, ordering, paging bounds and parameter layout
  # are exactly those produced by PostgresPage.
  defp benchmark_relation(sql) do
    rewritten =
      String.replace(
        sql,
        "FROM positions",
        "FROM #{@table}"
      )

    if rewritten == sql do
      raise """
      compiled query did not reference the positions relation
      """
    end

    rewritten
  end

  defp validate_first_page_shapes!(generic_sql, optimized_sql) do
    normalized_generic =
      normalize_sql(generic_sql)

    normalized_optimized =
      normalize_sql(optimized_sql)

    if String.contains?(
         normalized_generic,
         "UNION ALL"
       ) do
      raise """
      generic OR compiler unexpectedly produced UNION ALL
      """
    end

    if occurrences(
         normalized_generic,
         " OR "
       ) != 3 do
      raise """
      generic OR compiler did not produce the expected four-way OR
      """
    end

    if occurrences(
         normalized_optimized,
         "UNION ALL"
       ) != 3 do
      raise """
      specialized symmetry compiler did not produce four UNION ALL branches
      """
    end

    if String.contains?(
         normalized_optimized,
         " OR "
       ) do
      raise """
      specialized symmetry compiler unexpectedly produced OR
      """
    end

    if occurrences(
         normalized_optimized,
         "ORDER BY p.id"
       ) != 4 do
      raise """
      specialized symmetry compiler did not order every equality scan by id
      """
    end
  end

  defp validate_next_page_shapes!(generic_sql, optimized_sql) do
    validate_first_page_shapes!(
      generic_sql,
      optimized_sql
    )

    normalized_optimized =
      normalize_sql(optimized_sql)

    if occurrences(
         normalized_optimized,
         "p.id >"
       ) != 4 do
      raise """
      specialized symmetry compiler did not push the lower keyset bound
      into every branch
      """
    end

    if occurrences(
         normalized_optimized,
         "p.id <="
       ) != 4 do
      raise """
      specialized symmetry compiler did not push the high-water bound
      into every branch
      """
    end
  end

  defp assert_same_page!(page_name, generic_page, optimized_page) do
    if generic_page !=
         optimized_page do
      raise """
      generic OR and specialized symmetry compiler returned different
      #{page_name} pages.

      Generic OR:
      #{inspect(generic_page)}

      Specialized symmetry:
      #{inspect(optimized_page)}
      """
    end
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

  defp normalize_sql(sql) do
    sql
    |> String.replace(
      ~r/\s+/,
      " "
    )
    |> String.trim()
  end

  defp occurrences(string, fragment) do
    string
    |> String.split(fragment)
    |> length()
    |> Kernel.-(1)
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
  PostgreSQL production-compiler pawn-structure symmetry benchmark

  rows:       #{fixture.row_count}
  table size: #{fixture.table_size} bytes
  index size: #{fixture.index_size} bytes
  total size: #{fixture.total_size} bytes

  Comparing the generic OR compiler route with the specialized
  pawn-structure symmetry compiler route.
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
