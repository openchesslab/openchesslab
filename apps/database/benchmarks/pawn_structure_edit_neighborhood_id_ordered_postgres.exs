alias OpenChessLab.Database.PawnStructureEditNeighborhoodIdOrderedPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditNeighborhoodIdOrderedPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @pawn_structure_index "positions_pawn_structure_index"
  @covering_index "positions_pawn_id_covering_bench_index"

  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_keys 4_022

  def build(posting_count, selectivity) do
    encoded_structures =
      encoded_distance_two_structures()

    structure_count =
      length(encoded_structures)

    {white_keys, black_keys} =
      Enum.unzip(encoded_structures)

    row_count =
      posting_count * selectivity

    cleanup()
    clear_positions()

    setup_query!(
      """
      INSERT INTO positions (
        id,
        record,
        white_pawns,
        black_pawns
      )
      SELECT
        id,
        decode(
          lpad(
            to_hex(id),
            16,
            '0'
          ) ||
            repeat(
              '00',
              59
            ),
          'hex'
        ),
        CASE
          WHEN mod(id, $2::bigint) = 0
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
          WHEN mod(id, $2::bigint) = 0
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

    setup_query!(
      """
      SELECT setval(
        pg_get_serial_sequence(
          'positions',
          'id'
        ),
        $1::bigint,
        TRUE
      )
      """,
      [row_count]
    )

    setup_query!("VACUUM (ANALYZE) positions")

    %{
      row_count: row_count,
      structure_count: structure_count,
      white_keys: white_keys,
      black_keys: black_keys,
      table_size: relation_size("positions"),
      primary_key_size: relation_size("positions_pkey"),
      pawn_index_size: relation_size(@pawn_structure_index),
      total_size: total_relation_size("positions")
    }
  end

  def benchmark(
        %{row_count: row_count, white_keys: white_keys, black_keys: black_keys},
        posting_count,
        selectivity,
        page_size
      ) do
    requested_rows =
      page_size + 1

    pair_first_sql =
      pair_first_sql()

    pair_first_parameters = [
      white_keys,
      black_keys,
      requested_rows
    ]

    id_ordered_first_sql =
      id_ordered_first_sql()

    id_ordered_first_parameters = [
      white_keys,
      black_keys,
      requested_rows
    ]

    pair_first_ids =
      query_ids(
        pair_first_sql,
        pair_first_parameters
      )

    id_ordered_first_ids =
      query_ids(
        id_ordered_first_sql,
        id_ordered_first_parameters
      )

    validate_equal_results!(
      :first_page,
      pair_first_ids,
      id_ordered_first_ids
    )

    validate_ids!(
      pair_first_ids,
      min(posting_count, requested_rows),
      selectivity,
      nil
    )

    last_position_id =
      pair_first_ids
      |> Enum.take(page_size)
      |> List.last()

    pair_second_sql =
      pair_second_sql()

    pair_second_parameters = [
      white_keys,
      black_keys,
      last_position_id,
      row_count,
      requested_rows
    ]

    id_ordered_second_sql =
      id_ordered_second_sql()

    id_ordered_second_parameters = [
      white_keys,
      black_keys,
      last_position_id,
      row_count,
      requested_rows
    ]

    pair_second_ids =
      query_ids(
        pair_second_sql,
        pair_second_parameters
      )

    id_ordered_second_ids =
      query_ids(
        id_ordered_second_sql,
        id_ordered_second_parameters
      )

    validate_equal_results!(
      :second_page,
      pair_second_ids,
      id_ordered_second_ids
    )

    expected_second_count =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(requested_rows)

    validate_ids!(
      pair_second_ids,
      expected_second_count,
      selectivity,
      last_position_id
    )

    IO.puts("""
    PostgreSQL server version:
    #{server_version()}

    Existing positions primary-key index:
    #{index_definition("positions_pkey")}

    Existing pawn-structure index:
    #{index_definition(@pawn_structure_index)}

    Current pair-relation first-page plan:
    #{explain(pair_first_sql, pair_first_parameters)}

    ID-ordered candidate first-page plan without covering index:
    #{explain(id_ordered_first_sql, id_ordered_first_parameters)}

    Current pair-relation second-page plan:
    #{explain(pair_second_sql, pair_second_parameters)}

    ID-ordered candidate second-page plan without covering index:
    #{explain(id_ordered_second_sql, id_ordered_second_parameters)}
    """)

    IO.puts("""
    Benchmark without covering ID index

    The ID-ordered candidate has only the production indexes
    available here. If PostgreSQL chooses an ordered positions_pkey
    scan, it must visit the heap to read white_pawns and black_pawns.
    """)

    run_benchmark(
      pair_first_sql,
      pair_first_parameters,
      id_ordered_first_sql,
      id_ordered_first_parameters,
      pair_second_sql,
      pair_second_parameters,
      id_ordered_second_sql,
      id_ordered_second_parameters,
      posting_count,
      selectivity,
      page_size,
      expected_second_count,
      last_position_id,
      "id ordered: production indexes"
    )

    create_covering_index()

    covering_index_size =
      relation_size(@covering_index)

    IO.puts("""
    Benchmark-only covering ID index:
    #{index_definition(@covering_index)}

    covering ID index size: #{covering_index_size} bytes

    ID-ordered candidate first-page plan with covering index available:
    #{explain(id_ordered_first_sql, id_ordered_first_parameters)}

    ID-ordered candidate second-page plan with covering index available:
    #{explain(id_ordered_second_sql, id_ordered_second_parameters)}
    """)

    validate_equal_results!(
      :covering_first_page,
      pair_first_ids,
      query_ids(
        id_ordered_first_sql,
        id_ordered_first_parameters
      )
    )

    validate_equal_results!(
      :covering_second_page,
      pair_second_ids,
      query_ids(
        id_ordered_second_sql,
        id_ordered_second_parameters
      )
    )

    IO.puts("""
    Benchmark with covering ID index

    PostgreSQL now also has:

      (id) INCLUDE (white_pawns, black_pawns)

    available to satisfy the ordered scan without reading the
    positions heap, if the planner considers that strategy cheaper.
    """)

    run_benchmark(
      pair_first_sql,
      pair_first_parameters,
      id_ordered_first_sql,
      id_ordered_first_parameters,
      pair_second_sql,
      pair_second_parameters,
      id_ordered_second_sql,
      id_ordered_second_parameters,
      posting_count,
      selectivity,
      page_size,
      expected_second_count,
      last_position_id,
      "id ordered: covering index available"
    )
  end

  def cleanup do
    setup_query!("DROP INDEX IF EXISTS #{@covering_index}")
  end

  defp create_covering_index do
    setup_query!("""
    CREATE INDEX #{@covering_index}
    ON positions (id)
    INCLUDE (
      white_pawns,
      black_pawns
    )
    """)

    setup_query!("VACUUM (ANALYZE) positions")
  end

  defp run_benchmark(
         pair_first_sql,
         pair_first_parameters,
         id_ordered_first_sql,
         id_ordered_first_parameters,
         pair_second_sql,
         pair_second_parameters,
         id_ordered_second_sql,
         id_ordered_second_parameters,
         posting_count,
         selectivity,
         page_size,
         expected_second_count,
         last_position_id,
         id_ordered_label
       ) do
    requested_rows =
      page_size + 1

    Benchee.run(
      %{
        "pair relation: first page" => fn ->
          pair_first_sql
          |> query_ids(pair_first_parameters)
          |> validate_ids!(
            min(posting_count, requested_rows),
            selectivity,
            nil
          )
        end,
        "#{id_ordered_label}: first page" => fn ->
          id_ordered_first_sql
          |> query_ids(id_ordered_first_parameters)
          |> validate_ids!(
            min(posting_count, requested_rows),
            selectivity,
            nil
          )
        end,
        "pair relation: second page" => fn ->
          pair_second_sql
          |> query_ids(pair_second_parameters)
          |> validate_ids!(
            expected_second_count,
            selectivity,
            last_position_id
          )
        end,
        "#{id_ordered_label}: second page" => fn ->
          id_ordered_second_sql
          |> query_ids(id_ordered_second_parameters)
          |> validate_ids!(
            expected_second_count,
            selectivity,
            last_position_id
          )
        end
      },
      warmup: 1,
      time: 3,
      parallel: 1
    )
  end

  defp pair_first_sql do
    """
    SELECT
      p.id
    FROM unnest(
      $1::bigint[],
      $2::bigint[]
    ) AS pawn_structure_keys(
      white_pawns,
      black_pawns
    )
    JOIN positions AS p
      ON p.white_pawns =
        pawn_structure_keys.white_pawns
      AND p.black_pawns =
        pawn_structure_keys.black_pawns
    ORDER BY
      p.id
    LIMIT $3::bigint
    """
  end

  defp pair_second_sql do
    """
    SELECT
      p.id
    FROM unnest(
      $1::bigint[],
      $2::bigint[]
    ) AS pawn_structure_keys(
      white_pawns,
      black_pawns
    )
    JOIN positions AS p
      ON p.white_pawns =
        pawn_structure_keys.white_pawns
      AND p.black_pawns =
        pawn_structure_keys.black_pawns
      AND p.id > $3::bigint
      AND p.id <= $4::bigint
    ORDER BY
      p.id
    LIMIT $5::bigint
    """
  end

  defp id_ordered_first_sql do
    """
    WITH pawn_structure_keys AS MATERIALIZED (
      SELECT
        keys.white_pawns,
        keys.black_pawns
      FROM unnest(
        $1::bigint[],
        $2::bigint[]
      ) AS keys(
        white_pawns,
        black_pawns
      )
    )
    SELECT
      p.id
    FROM positions AS p
    WHERE
      (
        p.white_pawns,
        p.black_pawns
      ) IN (
        SELECT
          pawn_structure_keys.white_pawns,
          pawn_structure_keys.black_pawns
        FROM pawn_structure_keys
      )
    ORDER BY
      p.id
    LIMIT $3::bigint
    """
  end

  defp id_ordered_second_sql do
    """
    WITH pawn_structure_keys AS MATERIALIZED (
      SELECT
        keys.white_pawns,
        keys.black_pawns
      FROM unnest(
        $1::bigint[],
        $2::bigint[]
      ) AS keys(
        white_pawns,
        black_pawns
      )
    )
    SELECT
      p.id
    FROM positions AS p
    WHERE
      p.id > $3::bigint
      AND p.id <= $4::bigint
      AND (
        p.white_pawns,
        p.black_pawns
      ) IN (
        SELECT
          pawn_structure_keys.white_pawns,
          pawn_structure_keys.black_pawns
        FROM pawn_structure_keys
      )
    ORDER BY
      p.id
    LIMIT $5::bigint
    """
  end

  defp encoded_distance_two_structures do
    structures =
      EditDistance.neighborhood(
        @source_structure,
        2
      )

    if length(structures) != @expected_keys do
      raise """
      expected #{@expected_keys} distance-2 pawn-structure keys,
      got #{length(structures)}
      """
    end

    Enum.map(
      structures,
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

  defp query_ids(sql, parameters) do
    Repo
    |> SQL.query!(
      sql,
      parameters
    )
    |> Map.fetch!(:rows)
    |> Enum.map(fn [id] ->
      id
    end)
  end

  defp validate_equal_results!(page, pair_ids, candidate_ids) do
    if pair_ids != candidate_ids do
      raise """
      ID-ordered candidate results differ from the current
      pair-relation results for #{page}.

      Pair relation:
      #{inspect(pair_ids)}

      ID ordered:
      #{inspect(candidate_ids)}
      """
    end

    :ok
  end

  defp validate_ids!(ids, expected_count, selectivity, after_position_id) do
    if length(ids) != expected_count do
      raise """
      expected #{expected_count} result rows,
      got #{length(ids)}
      """
    end

    if ids != Enum.sort(ids) do
      raise """
      result IDs are not ordered
      """
    end

    if !Enum.all?(
         ids,
         fn id ->
           rem(id, selectivity) == 0
         end
       ) do
      raise """
      result contains a row outside the benchmark
      pawn-structure neighborhood
      """
    end

    case {after_position_id, ids} do
      {nil, _ids} ->
        :ok

      {_after_position_id, []} ->
        :ok

      {
        after_position_id,
        [first_id | _remaining]
      }
      when first_id > after_position_id ->
        :ok

      {
        after_position_id,
        [first_id | _remaining]
      } ->
        raise """
        expected page to start after #{after_position_id},
        got #{first_id}
        """
    end

    ids
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
      fn [line] ->
        line
      end
    )
  end

  defp server_version do
    case SQL.query!(
           Repo,
           "SHOW server_version",
           []
         ).rows do
      [[version]] ->
        version
    end
  end

  defp relation_size(relation) do
    case SQL.query!(
           Repo,
           """
           SELECT pg_relation_size(
             to_regclass($1::text)
           )
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
           SELECT pg_total_relation_size(
             to_regclass($1::text)
           )
           """,
           [relation]
         ).rows do
      [[size]] ->
        size
    end
  end

  defp index_definition(index) do
    case SQL.query!(
           Repo,
           """
           SELECT pg_get_indexdef(
             to_regclass($1::text)
           )
           """,
           [index]
         ).rows do
      [[definition]] ->
        definition
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

  defp clear_positions do
    setup_query!("""
    TRUNCATE TABLE positions
    RESTART IDENTITY
    CASCADE
    """)
  end
end

database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use the dedicated benchmark database.

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
    "PAWN_ID_ORDER_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_ID_ORDER_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_ID_ORDER_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_ID_ORDER_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_ID_ORDER_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_ID_ORDER_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count < page_size * 2 do
  raise """
  PAWN_ID_ORDER_BENCH_POSTINGS must be at least twice
  PAWN_ID_ORDER_BENCH_PAGE_SIZE so the benchmark has a
  full second page.
  """
end

try do
  IO.puts("""
  Building ID-ordered pawn edit-neighborhood benchmark fixture...

  neighborhood matches: #{posting_count}
  selectivity:          1/#{selectivity}
  rows:                 #{posting_count * selectivity}
  neighborhood keys:    4_022
  page size:            #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  ID-ordered pawn edit-neighborhood paging benchmark

  rows:                  #{fixture.row_count}
  positions table:       #{fixture.table_size} bytes
  positions primary key: #{fixture.primary_key_size} bytes
  pawn paging index:     #{fixture.pawn_index_size} bytes
  total positions size:  #{fixture.total_size} bytes
  neighborhood keys:     #{fixture.structure_count}

  This compares:

    * the current key-driven pair relation, which probes
      (white_pawns, black_pawns, id) once per neighborhood key
      and then globally orders the matches

    * an ID-ordered semi-join candidate, where PostgreSQL can hash
      the 4,022 neighborhood keys once and scan positions in ID
      order, allowing LIMIT to stop execution after enough matches

  The second phase adds a benchmark-only covering index:

      (id) INCLUDE (white_pawns, black_pawns)

  to determine whether heap access is the limiting factor in the
  ID-ordered strategy.

  No production schema is changed by this benchmark.
  """)

  Benchmark.benchmark(
    fixture,
    posting_count,
    selectivity,
    page_size
  )
after
  Benchmark.cleanup()
end
