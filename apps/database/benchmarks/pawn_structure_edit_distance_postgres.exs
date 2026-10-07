alias OpenChessLab.Database.PawnStructureEditDistancePostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditDistancePostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "ocl_pawn_edit_distance_bench"
  @index "ocl_pawn_edit_distance_bench_paging_idx"

  # White:
  #   a3 b4 c4 d4 e2 f2 g2 h3
  #
  # Black:
  #   a6 b7 c6 d6 e6 f5 g5 h6
  #
  # This is the same asymmetric sixteen-pawn source used by the previous
  # pawn-neighborhood benchmarks.
  #
  # Under the current elementary edit vocabulary it has:
  #
  #   * 32 distinct single-rank neighbors
  #   * 44 distinct capture-like neighbors
  #   * 16 distinct single-pawn removals
  #   * 92 distinct distance-one neighbors
  #   * 4,022 distinct structures within distance <= 2
  #
  # The benchmark intentionally does not expand those 4,022 keys into
  # thousands of UNION ALL branches. Instead it sends the keys as two
  # PostgreSQL bigint arrays and exposes them as a relation with unnest/2.
  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_distance_one_keys 92
  @expected_distance_two_keys 4_022

  def build(posting_count, selectivity) do
    row_count =
      posting_count *
        selectivity

    encoded_structures =
      encoded_distance_two_structures()

    structure_count =
      length(encoded_structures)

    {
      white_keys,
      black_keys
    } =
      encoded_key_arrays(encoded_structures)

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
            THEN (
              $3::bigint[]
            )[
              mod(
                (id / $2::bigint) - 1,
                #{structure_count}
              ) + 1
            ]
          ELSE id
        END,
        CASE
          WHEN mod(
            id,
            $2::bigint
          ) = 0
            THEN (
              $4::bigint[]
            )[
              mod(
                (id / $2::bigint) - 1,
                #{structure_count}
              ) + 1
            ]
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
        white_keys,
        black_keys
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
      structure_count: structure_count,
      table_size: relation_size(@table),
      index_size: relation_size(@index),
      total_size: total_relation_size(@table)
    }
  end

  def benchmark(posting_count, selectivity, page_size, row_count) do
    encoded_structures =
      encoded_distance_two_structures()

    {
      white_keys,
      black_keys
    } =
      encoded_key_arrays(encoded_structures)

    {
      relation_first_sql,
      relation_first_parameters
    } =
      relation_first_page(
        white_keys,
        black_keys,
        page_size
      )

    {
      predicate_first_sql,
      predicate_first_parameters
    } =
      predicate_first_page(
        white_keys,
        black_keys,
        page_size
      )

    relation_first_page =
      query_page(
        relation_first_sql,
        relation_first_parameters
      )

    predicate_first_page =
      query_page(
        predicate_first_sql,
        predicate_first_parameters
      )

    assert_same_page!(
      "first",
      relation_first_page,
      predicate_first_page
    )

    expected_first_page_size =
      min(
        posting_count,
        page_size
      )

    validate_page!(
      relation_first_page,
      row_count,
      expected_first_page_size,
      selectivity
    )

    last_position_id =
      relation_first_page
      |> Map.fetch!(:position_ids)
      |> List.last()

    {
      relation_second_sql,
      relation_second_parameters
    } =
      relation_next_page(
        white_keys,
        black_keys,
        row_count,
        last_position_id,
        page_size
      )

    {
      predicate_second_sql,
      predicate_second_parameters
    } =
      predicate_next_page(
        white_keys,
        black_keys,
        row_count,
        last_position_id,
        page_size
      )

    relation_second_page =
      query_page(
        relation_second_sql,
        relation_second_parameters
      )

    predicate_second_page =
      query_page(
        predicate_second_sql,
        predicate_second_parameters
      )

    assert_same_page!(
      "second",
      relation_second_page,
      predicate_second_page
    )

    expected_second_page_size =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(page_size)

    validate_page!(
      relation_second_page,
      row_count,
      expected_second_page_size,
      selectivity
    )

    IO.puts("""
    Array-key relation route

    First-page plan:
    #{explain(relation_first_sql,
    relation_first_parameters)}

    Second-page plan:
    #{explain(relation_second_sql,
    relation_second_parameters)}

    Generic EXISTS predicate route

    First-page plan:
    #{explain(predicate_first_sql,
    predicate_first_parameters)}

    Second-page plan:
    #{explain(predicate_second_sql,
    predicate_second_parameters)}
    """)

    Benchee.run(
      %{
        "4022-key relation: first page" => fn ->
          relation_first_sql
          |> query_page(relation_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "4022-key relation: second page" => fn ->
          relation_second_sql
          |> query_page(relation_second_parameters)
          |> validate_page!(
            row_count,
            expected_second_page_size,
            selectivity
          )
        end,
        "4022-key EXISTS: first page" => fn ->
          predicate_first_sql
          |> query_page(predicate_first_parameters)
          |> validate_page!(
            row_count,
            expected_first_page_size,
            selectivity
          )
        end,
        "4022-key EXISTS: second page" => fn ->
          predicate_second_sql
          |> query_page(predicate_second_parameters)
          |> validate_page!(
            row_count,
            expected_second_page_size,
            selectivity
          )
        end,
        "distance-2 key generation" => fn ->
          case encoded_distance_two_structures() do
            structures
            when length(structures) ==
                   @expected_distance_two_keys ->
              structures

            structures ->
              raise """
              expected #{@expected_distance_two_keys} encoded structures,
              got #{length(structures)}
              """
          end
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

  defp relation_first_page(white_keys, black_keys, page_size) do
    sql = """
    SELECT
      COALESCE(
        (
          SELECT max(id)
          FROM #{@table}
        ),
        0
      )::bigint AS maximum_position_id,
      p.id
    FROM unnest(
      $1::bigint[],
      $2::bigint[]
    ) AS keys(
      white_pawns,
      black_pawns
    )
    JOIN #{@table} AS p
      ON p.white_pawns = keys.white_pawns
      AND p.black_pawns = keys.black_pawns
    ORDER BY
      p.id
    LIMIT $3::bigint
    """

    {
      sql,
      [
        white_keys,
        black_keys,
        page_size
      ]
    }
  end

  defp relation_next_page(
         white_keys,
         black_keys,
         maximum_position_id,
         last_position_id,
         page_size
       ) do
    sql = """
    SELECT
      $3::bigint AS maximum_position_id,
      p.id
    FROM unnest(
      $1::bigint[],
      $2::bigint[]
    ) AS keys(
      white_pawns,
      black_pawns
    )
    JOIN #{@table} AS p
      ON p.white_pawns = keys.white_pawns
      AND p.black_pawns = keys.black_pawns
    WHERE
      p.id > $4::bigint
      AND p.id <= $3::bigint
    ORDER BY
      p.id
    LIMIT $5::bigint
    """

    {
      sql,
      [
        white_keys,
        black_keys,
        maximum_position_id,
        last_position_id,
        page_size
      ]
    }
  end

  defp predicate_first_page(white_keys, black_keys, page_size) do
    sql = """
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
      EXISTS (
        SELECT 1
        FROM unnest(
          $1::bigint[],
          $2::bigint[]
        ) AS keys(
          white_pawns,
          black_pawns
        )
        WHERE
          keys.white_pawns = p.white_pawns
          AND keys.black_pawns = p.black_pawns
      )
    ORDER BY
      p.id
    LIMIT $3::bigint
    """

    {
      sql,
      [
        white_keys,
        black_keys,
        page_size
      ]
    }
  end

  defp predicate_next_page(
         white_keys,
         black_keys,
         maximum_position_id,
         last_position_id,
         page_size
       ) do
    sql = """
    SELECT
      $3::bigint AS maximum_position_id,
      p.id
    FROM #{@table} AS p
    WHERE
      p.id > $4::bigint
      AND p.id <= $3::bigint
      AND EXISTS (
        SELECT 1
        FROM unnest(
          $1::bigint[],
          $2::bigint[]
        ) AS keys(
          white_pawns,
          black_pawns
        )
        WHERE
          keys.white_pawns = p.white_pawns
          AND keys.black_pawns = p.black_pawns
      )
    ORDER BY
      p.id
    LIMIT $5::bigint
    """

    {
      sql,
      [
        white_keys,
        black_keys,
        maximum_position_id,
        last_position_id,
        page_size
      ]
    }
  end

  defp distance_two_structures do
    distance_one =
      EditDistance.neighborhood(
        @source_structure,
        1
      )

    if length(distance_one) !=
         @expected_distance_one_keys + 1 do
      raise """
      benchmark source structure must produce #{@expected_distance_one_keys}
      distinct distance-one neighbors, got #{length(distance_one) - 1}
      """
    end

    structures =
      EditDistance.neighborhood(
        @source_structure,
        2
      )

    if length(structures) !=
         @expected_distance_two_keys do
      raise """
      benchmark source structure must produce #{@expected_distance_two_keys}
      distinct structures within distance <= 2, got #{length(structures)}
      """
    end

    structures
  end

  defp encoded_distance_two_structures do
    Enum.map(
      distance_two_structures(),
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

  defp encoded_key_arrays(encoded_structures) do
    Enum.unzip(encoded_structures)
  end

  defp assert_same_page!(page_name, left, right) do
    if left != right do
      raise """
      array-key relation and EXISTS predicate returned different
      #{page_name} pages.

      Relation:
      #{inspect(left)}

      EXISTS:
      #{inspect(right)}
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
      page contains a position outside the edit-distance fixture
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

database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database.

    Example:

        ecto://openchesslab:openchesslab@localhost/openchesslab_bench
    """

if URI.parse(database_url).path !=
     "/openchesslab_bench" do
  raise """
  benchmark must use the dedicated openchesslab_bench database.

  DATABASE_URL points to:

      #{database_url}
  """
end

posting_count =
  System.get_env(
    "PAWN_EDIT_DISTANCE_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_EDIT_DISTANCE_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_EDIT_DISTANCE_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_EDIT_DISTANCE_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_EDIT_DISTANCE_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_EDIT_DISTANCE_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count <
     page_size * 2 do
  raise """
  PAWN_EDIT_DISTANCE_BENCH_POSTINGS must be at least twice
  PAWN_EDIT_DISTANCE_BENCH_PAGE_SIZE so the benchmark has a
  full second page.
  """
end

try do
  IO.puts("""
  Building PostgreSQL pawn edit-distance fixture...

  neighborhood matches: #{posting_count}
  selectivity:          1/#{selectivity}
  rows:                 #{posting_count * selectivity}
  distance:             <= 2
  page size:            #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  PostgreSQL pawn edit-distance benchmark

  rows:              #{fixture.row_count}
  table size:        #{fixture.table_size} bytes
  index size:        #{fixture.index_size} bytes
  total size:        #{fixture.total_size} bytes
  neighborhood keys: #{fixture.structure_count}

  Comparing two compact ways to expose the same 4,022 exact
  pawn-structure keys to PostgreSQL:

    * an unnested key relation joined to positions
    * an unnested key relation used through EXISTS

  Neither route expands the neighborhood into thousands of
  UNION ALL branches.
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
