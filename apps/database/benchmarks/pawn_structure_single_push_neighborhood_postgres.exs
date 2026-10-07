alias OpenChessLab.Database.PawnStructureSinglePushNeighborhoodPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureSinglePushNeighborhoodPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.PawnStructure
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "openchesslab_pawn_structure_single_push_neighborhood_benchmark"
  @index "#{@table}_paging_index"

  @source_structure %PawnStructure{
    white: 0x000000000000FF00,
    black: 0x00FF000000000000
  }

  def build(posting_count, selectivity) do
    row_count =
      posting_count *
        selectivity

    encoded_structures =
      encoded_neighborhood()

    structure_count =
      length(encoded_structures)

    drop_table()

    setup_query!("""
    CREATE TABLE #{@table} (
      id bigint PRIMARY KEY,
      white_pawns bigint NOT NULL,
      black_pawns bigint NOT NULL
    )
    """)

    white_case =
      fixture_case(
        structure_count,
        0
      )

    black_case =
      fixture_case(
        structure_count,
        1
      )

    parameters =
      [
        row_count,
        selectivity
        | Enum.flat_map(
            encoded_structures,
            fn
              {
                white_pawns,
                black_pawns
              } ->
                [
                  white_pawns,
                  black_pawns
                ]
            end
          )
      ]

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
                (id / $2::bigint) - 1,
                #{structure_count}
              )
                #{white_case}
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
                (id / $2::bigint) - 1,
                #{structure_count}
              )
                #{black_case}
              END
          ELSE -id
        END
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      parameters
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
      structure_count: structure_count,
      table_size: relation_size(@table),
      index_size: relation_size(@index),
      total_size: total_relation_size(@table)
    }
  end

  def benchmark(posting_count, selectivity, page_size, row_count) do
    structures =
      neighborhood_structures()

    generic_query =
      structures
      |> Enum.map(&PositionQuery.pawn_structure/1)
      |> PositionQuery.any()

    optimized_query =
      PositionQuery.pawn_structures(structures)

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
      optimized_first_sql,
      length(structures)
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
      optimized_next_sql,
      length(structures)
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

    Specialized bounded-set compiler route

    First-page plan:
    #{explain(optimized_first_sql,
    optimized_first_parameters)}

    Second-page plan:
    #{explain(optimized_next_sql,
    optimized_next_parameters)}
    """)

    Benchee.run(
      %{
        "generic OR: first page" => fn ->
          generic_first_sql
          |> query_page(generic_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "generic OR: second page" => fn ->
          generic_next_sql
          |> query_page(generic_next_parameters)
          |> validate_page!(
            row_count,
            expected_second_page_size,
            selectivity
          )
        end,
        "bounded set: first page" => fn ->
          optimized_first_sql
          |> query_page(optimized_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "bounded set: second page" => fn ->
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

  defp neighborhood_structures do
    structures =
      [
        @source_structure
        | PawnStructure.single_pushes(@source_structure)
      ]

    if length(structures) != 17 do
      raise """
      benchmark source structure must produce 17 neighborhood keys,
      got #{length(structures)}
      """
    end

    structures
  end

  defp encoded_neighborhood do
    Enum.map(
      neighborhood_structures(),
      fn structure ->
        case PositionPawnStructureCodec.encode(structure) do
          {:ok, encoded_structure} ->
            encoded_structure

          {:error, reason} ->
            raise """
            could not encode benchmark pawn structure:

            #{inspect(reason)}
            """
        end
      end
    )
  end

  defp fixture_case(structure_count, offset) do
    0..(structure_count - 1)
    |> Enum.map_join(
      "\n                ",
      fn index ->
        parameter =
          3 +
            index * 2 +
            offset

        "WHEN #{index} THEN $#{parameter}::bigint"
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

  defp validate_first_page_shapes!(generic_sql, optimized_sql, structure_count) do
    normalized_generic =
      normalize_sql(generic_sql)

    normalized_optimized =
      normalize_sql(optimized_sql)

    expected_joins =
      structure_count - 1

    if occurrences(
         normalized_generic,
         " OR "
       ) != expected_joins do
      raise """
      generic OR compiler did not produce #{structure_count} predicates
      """
    end

    if String.contains?(
         normalized_generic,
         "UNION ALL"
       ) do
      raise """
      generic OR compiler unexpectedly produced UNION ALL
      """
    end

    if occurrences(
         normalized_optimized,
         "UNION ALL"
       ) != expected_joins do
      raise """
      bounded-set compiler did not produce #{structure_count} ordered branches
      """
    end

    if String.contains?(
         normalized_optimized,
         " OR "
       ) do
      raise """
      bounded-set compiler unexpectedly produced OR
      """
    end

    if occurrences(
         normalized_optimized,
         "ORDER BY p.id"
       ) != structure_count do
      raise """
      bounded-set compiler did not order every equality scan by id
      """
    end
  end

  defp validate_next_page_shapes!(generic_sql, optimized_sql, structure_count) do
    validate_first_page_shapes!(
      generic_sql,
      optimized_sql,
      structure_count
    )

    normalized_optimized =
      normalize_sql(optimized_sql)

    if occurrences(
         normalized_optimized,
         "p.id >"
       ) != structure_count do
      raise """
      bounded-set compiler did not push the lower keyset bound
      into every branch
      """
    end

    if occurrences(
         normalized_optimized,
         "p.id <="
       ) != structure_count do
      raise """
      bounded-set compiler did not push the high-water bound
      into every branch
      """
    end
  end

  defp assert_same_page!(page_name, generic_page, optimized_page) do
    if generic_page !=
         optimized_page do
      raise """
      generic OR and bounded-set compiler returned different
      #{page_name} pages.

      Generic OR:
      #{inspect(generic_page)}

      Bounded set:
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

    if length(result.position_ids) != expected_count do
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
      page contains a position outside the neighborhood fixture
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
    "PAWN_NEIGHBORHOOD_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_NEIGHBORHOOD_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_NEIGHBORHOOD_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_NEIGHBORHOOD_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_NEIGHBORHOOD_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_NEIGHBORHOOD_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count <
     page_size * 2 do
  raise """
  PAWN_NEIGHBORHOOD_BENCH_POSTINGS must be at least twice
  PAWN_NEIGHBORHOOD_BENCH_PAGE_SIZE so the benchmark has a full
  second page.
  """
end

try do
  IO.puts("""
  Building PostgreSQL single-push pawn-structure neighborhood fixture...

  neighborhood matches: #{posting_count}
  selectivity:          1/#{selectivity}
  rows:                 #{posting_count * selectivity}
  neighborhood keys:    17
  page size:            #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  PostgreSQL single-push pawn-structure neighborhood benchmark

  rows:              #{fixture.row_count}
  table size:        #{fixture.table_size} bytes
  index size:        #{fixture.index_size} bytes
  total size:        #{fixture.total_size} bytes
  neighborhood keys: #{fixture.structure_count}

  Comparing the generic OR compiler route with the production
  bounded pawn-structure set compiler route.
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
