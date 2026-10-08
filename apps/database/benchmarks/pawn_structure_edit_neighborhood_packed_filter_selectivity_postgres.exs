alias OpenChessLab.Database.PawnStructureEditNeighborhoodPackedFilterSelectivityPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditNeighborhoodPackedFilterSelectivityPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.PawnStructure
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @pair_index "positions_pawn_structure_index"

  @packed_expression_index "positions_pawn_structure_packed_bench_index"
  @covering_id_index "positions_pawn_id_covering_bench_index"
  @forced_key_table "pawn_structure_forced_id_order_bench_keys"

  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_keys 4_022

  def build(row_count, selectivity) do
    query =
      PositionQuery.pawn_structure_edit_neighborhood(
        @source_structure,
        2
      )

    structures =
      neighborhood_structures!(query)

    encoded_structures =
      Enum.map(
        structures,
        &encode_structure!/1
      )

    {white_keys, black_keys} =
      Enum.unzip(encoded_structures)

    packed_keys =
      Enum.map(
        encoded_structures,
        &pack_encoded_structure/1
      )

    validate_packed_keys!(packed_keys)

    posting_count =
      div(
        row_count,
        selectivity
      )

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
          WHEN mod(
            id,
            $2::bigint
          ) = 0
            THEN (
              $3::bigint[]
            )[
              mod(
                (id / $2::bigint) - 1,
                #{@expected_keys}
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
                #{@expected_keys}
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
      query: query,
      row_count: row_count,
      posting_count: posting_count,
      selectivity: selectivity,
      packed_keys: packed_keys,
      table_size: relation_size("positions"),
      primary_key_size: relation_size("positions_pkey"),
      pair_index_size: relation_size(@pair_index),
      record_index_size: relation_size("positions_record_unique"),
      total_size: total_relation_size("positions")
    }
  end

  def benchmark(
        %{
          query: query,
          row_count: row_count,
          posting_count: posting_count,
          selectivity: selectivity,
          packed_keys: packed_keys
        },
        page_size
      ) do
    requested_rows =
      page_size + 1

    {pair_first_sql, pair_first_parameters} =
      compile_pair_first!(
        query,
        requested_rows
      )

    packed_first_sql =
      packed_first_sql()

    packed_first_parameters = [
      packed_keys,
      requested_rows
    ]

    pair_first_rows =
      query_rows(
        pair_first_sql,
        pair_first_parameters
      )

    packed_first_rows =
      query_rows(
        packed_first_sql,
        packed_first_parameters
      )

    validate_equal_rows!(
      :first_page,
      pair_first_rows,
      packed_first_rows
    )

    validate_rows!(
      pair_first_rows,
      row_count,
      min(
        posting_count,
        requested_rows
      ),
      selectivity,
      nil
    )

    last_position_id =
      pair_first_rows
      |> position_ids()
      |> Enum.take(page_size)
      |> List.last()

    {pair_second_sql, pair_second_parameters} =
      compile_pair_second!(
        query,
        row_count,
        last_position_id,
        requested_rows
      )

    packed_second_sql =
      packed_second_sql()

    packed_second_parameters = [
      packed_keys,
      row_count,
      last_position_id,
      requested_rows
    ]

    pair_second_rows =
      query_rows(
        pair_second_sql,
        pair_second_parameters
      )

    packed_second_rows =
      query_rows(
        packed_second_sql,
        packed_second_parameters
      )

    validate_equal_rows!(
      :second_page,
      pair_second_rows,
      packed_second_rows
    )

    expected_second_count =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(requested_rows)

    validate_rows!(
      pair_second_rows,
      row_count,
      expected_second_count,
      selectivity,
      last_position_id
    )

    pair_first_plan =
      explain(
        pair_first_sql,
        pair_first_parameters
      )

    packed_first_plan =
      explain(
        packed_first_sql,
        packed_first_parameters
      )

    pair_second_plan =
      explain(
        pair_second_sql,
        pair_second_parameters
      )

    packed_second_plan =
      explain(
        packed_second_sql,
        packed_second_parameters
      )

    validate_pair_plan!(
      :first_page,
      pair_first_plan
    )

    validate_pair_plan!(
      :second_page,
      pair_second_plan
    )

    validate_packed_filter_plan!(
      :first_page,
      packed_first_plan
    )

    validate_packed_filter_plan!(
      :second_page,
      packed_second_plan
    )

    IO.puts("""
    PostgreSQL server version:
    #{server_version()}

    selectivity:
    1/#{selectivity}

    expected matches:
    #{posting_count}

    Existing positions primary-key index:
    #{index_definition("positions_pkey")}

    Existing production pawn-structure index:
    #{index_definition(@pair_index)}

    Current production pair-relation first-page plan:
    #{pair_first_plan}

    Packed filter first-page plan:
    #{packed_first_plan}

    Current production pair-relation second-page plan:
    #{pair_second_plan}

    Packed filter second-page plan:
    #{packed_second_plan}
    """)

    Benchee.run(
      %{
        "production pair relation: first page" => fn ->
          pair_first_sql
          |> query_rows(pair_first_parameters)
          |> validate_rows!(
            row_count,
            min(
              posting_count,
              requested_rows
            ),
            selectivity,
            nil
          )
        end,
        "packed filter: first page" => fn ->
          packed_first_sql
          |> query_rows(packed_first_parameters)
          |> validate_rows!(
            row_count,
            min(
              posting_count,
              requested_rows
            ),
            selectivity,
            nil
          )
        end,
        "production pair relation: second page" => fn ->
          pair_second_sql
          |> query_rows(pair_second_parameters)
          |> validate_rows!(
            row_count,
            expected_second_count,
            selectivity,
            last_position_id
          )
        end,
        "packed filter: second page" => fn ->
          packed_second_sql
          |> query_rows(packed_second_parameters)
          |> validate_rows!(
            row_count,
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

  def benchmark_bounded(fixture, page_size, budgets) do
    %{
      query: query,
      row_count: row_count,
      packed_keys: packed_keys,
      selectivity: selectivity
    } = fixture

    requested_rows = page_size + 1

    {pair_first_sql, pair_first_params} =
      compile_pair_first!(query, requested_rows)

    first_expected = query_rows(pair_first_sql, pair_first_params)

    last_position_id =
      first_expected
      |> position_ids()
      |> Enum.take(page_size)
      |> List.last()

    {pair_second_sql, pair_second_params} =
      compile_pair_second!(
        query,
        row_count,
        last_position_id,
        requested_rows
      )

    second_expected = query_rows(pair_second_sql, pair_second_params)

    pages = [
      {
        :first,
        nil,
        pair_first_sql,
        pair_first_params,
        first_expected
      },
      {
        :second,
        last_position_id,
        pair_second_sql,
        pair_second_params,
        second_expected
      }
    ]

    Enum.each(budgets, fn budget ->
      Enum.each(pages, fn {page, after_id, pair_sql, pair_params, expected} ->
        sql = bounded_sql(page)

        params =
          case page do
            :first ->
              [budget, packed_keys, requested_rows]

            :second ->
              [
                after_id,
                row_count,
                budget,
                packed_keys,
                requested_rows
              ]
          end

        candidate_rows = query_rows(sql, params)

        fallback? = length(candidate_rows) < requested_rows

        actual =
          if fallback? do
            query_rows(pair_sql, pair_params)
          else
            candidate_rows
          end

        validate_equal_rows!(
          {page, budget},
          expected,
          actual
        )

        plan = explain(sql, params)

        validate_bounded_plan!(page, budget, plan)

        IO.puts("""

        ============================================================
        Bounded adaptive scan
        ============================================================
        Selectivity: 1/#{selectivity}
        Page:        #{page}
        Budget:      #{budget}
        Found:       #{length(candidate_rows)}
        Required:    #{requested_rows}
        Fallback:    #{fallback?}

        Relevant execution plan:
        #{bounded_plan_summary(plan)}
        """)

        Benchee.run(
          %{
            "pair baseline" => fn ->
              rows = query_rows(pair_sql, pair_params)
              validate_equal_rows!(page, expected, rows)
            end,
            "bounded adaptive" => fn ->
              rows =
                adaptive_bounded_rows(
                  sql,
                  params,
                  pair_sql,
                  pair_params,
                  requested_rows
                )

              validate_equal_rows!(page, expected, rows)
            end
          },
          warmup: 1,
          time: 3,
          parallel: 1
        )
      end)
    end)
  end

  defp bounded_sql(:first) do
    """
    WITH candidates AS MATERIALIZED (
      SELECT
        p.id,
        p.white_pawns,
        p.black_pawns
      FROM positions AS p
      ORDER BY p.id
      LIMIT $1::bigint
    )
    SELECT
      COALESCE(
        (SELECT max(id) FROM positions),
        0
      )::bigint AS maximum_position_id,
      c.id
    FROM candidates AS c
    WHERE (
      int8send(c.white_pawns) ||
      int8send(c.black_pawns)
    ) = ANY($2::bytea[])
    ORDER BY c.id
    LIMIT $3::bigint
    """
  end

  defp bounded_sql(:second) do
    """
    WITH candidates AS MATERIALIZED (
      SELECT
        p.id,
        p.white_pawns,
        p.black_pawns
      FROM positions AS p
      WHERE p.id > $1::bigint
        AND p.id <= $2::bigint
      ORDER BY p.id
      LIMIT $3::bigint
    )
    SELECT
      $2::bigint AS maximum_position_id,
      c.id
    FROM candidates AS c
    WHERE (
      int8send(c.white_pawns) ||
      int8send(c.black_pawns)
    ) = ANY($4::bytea[])
    ORDER BY c.id
    LIMIT $5::bigint
    """
  end

  defp adaptive_bounded_rows(bounded_sql, bounded_params, pair_sql, pair_params, requested_rows) do
    rows = query_rows(bounded_sql, bounded_params)

    if length(rows) == requested_rows do
      rows
    else
      query_rows(pair_sql, pair_params)
    end
  end

  defp validate_bounded_plan!(page, budget, plan) do
    if !(String.contains?(plan, "CTE Scan") and
           String.contains?(plan, "positions_pkey on positions p")) do
      raise """
      Bounded scan does not use the expected materialized
      candidate scan and primary-key index.

      Page: #{page}
      Budget: #{budget}

      #{plan}
      """
    end

    if String.contains?(plan, "Seq Scan on positions p") do
      raise """
      Bounded scan unexpectedly uses a sequential table scan.

      Page: #{page}
      Budget: #{budget}

      #{plan}
      """
    end

    :ok
  end

  defp bounded_plan_summary(plan) do
    plan
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, "Limit ") or
        String.contains?(line, "CTE Scan") or
        String.contains?(line, "Index Scan") or
        String.contains?(line, "Rows Removed by Filter") or
        String.contains?(line, "Execution Time:") or
        String.contains?(line, "Sort Method:")
    end)
    |> Enum.map_join("\n", fn line ->
      if String.contains?(line, "Filter:") do
        "[filter omitted]"
      else
        line
      end
    end)
  end

  def cleanup do
    setup_query!("DROP INDEX IF EXISTS #{@packed_expression_index}")

    setup_query!("DROP INDEX IF EXISTS #{@covering_id_index}")

    setup_query!("DROP TABLE IF EXISTS #{@forced_key_table}")
  end

  defp compile_pair_first!(query, requested_rows) do
    case PostgresPage.compile_first(
           query,
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

      {
        :error,
        reason
      } ->
        raise """
        could not compile production first page:

        #{inspect(reason)}
        """
    end
  end

  defp compile_pair_second!(query, maximum_position_id, last_position_id, requested_rows) do
    case PostgresPage.compile_next(
           query,
           maximum_position_id,
           last_position_id,
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

      {
        :error,
        reason
      } ->
        raise """
        could not compile production second page:

        #{inspect(reason)}
        """
    end
  end

  defp packed_first_sql do
    """
    SELECT
      COALESCE(
        (
          SELECT max(id)
          FROM positions
        ),
        0
      )::bigint AS maximum_position_id,
      p.id
    FROM positions AS p
    WHERE
      (
        int8send(p.white_pawns) ||
          int8send(p.black_pawns)
      ) = ANY($1::bytea[])
    ORDER BY
      p.id
    LIMIT $2::bigint
    """
  end

  defp packed_second_sql do
    """
    SELECT
      $2::bigint AS maximum_position_id,
      p.id
    FROM positions AS p
    WHERE
      (
        int8send(p.white_pawns) ||
          int8send(p.black_pawns)
      ) = ANY($1::bytea[])
      AND p.id > $3::bigint
      AND p.id <= $2::bigint
    ORDER BY
      p.id
    LIMIT $4::bigint
    """
  end

  defp neighborhood_structures!({:pawn_structure_edit_neighborhood, structures})
       when is_list(structures) do
    if length(structures) !=
         @expected_keys do
      raise """
      expected #{@expected_keys} pawn-structure keys,
      got #{length(structures)}
      """
    end

    structures
  end

  defp neighborhood_structures!(query) do
    raise """
    expected pawn-structure edit-neighborhood query, got:

    #{inspect(query)}
    """
  end

  defp encode_structure!(structure) do
    case PositionPawnStructureCodec.encode(structure) do
      {
        :ok,
        encoded_structure
      } ->
        encoded_structure

      {
        :error,
        reason
      } ->
        raise """
        could not encode benchmark pawn structure:

        #{inspect(reason)}
        """
    end
  end

  defp pack_encoded_structure({white_pawns, black_pawns}) do
    <<
      white_pawns::signed-big-integer-size(64),
      black_pawns::signed-big-integer-size(64)
    >>
  end

  defp validate_packed_keys!(packed_keys) do
    if length(packed_keys) !=
         @expected_keys do
      raise """
      expected #{@expected_keys} packed keys,
      got #{length(packed_keys)}
      """
    end

    if !Enum.all?(
         packed_keys,
         &(byte_size(&1) == 16)
       ) do
      raise """
      every packed pawn-structure key must contain exactly 16 bytes
      """
    end

    packed_keys
  end

  defp query_rows(sql, parameters) do
    SQL.query!(
      Repo,
      sql,
      parameters
    ).rows
  end

  defp validate_equal_rows!(page, pair_rows, packed_rows) do
    if pair_rows != packed_rows do
      raise """
      packed-filter results differ from the production
      pair-relation results for #{page}.

      Production pair relation:
      #{inspect(pair_rows)}

      Packed filter:
      #{inspect(packed_rows)}
      """
    end

    :ok
  end

  defp validate_rows!(
         rows,
         expected_maximum_position_id,
         expected_count,
         selectivity,
         after_position_id
       ) do
    if length(rows) !=
         expected_count do
      raise """
      expected #{expected_count} rows,
      got #{length(rows)}
      """
    end

    Enum.each(
      rows,
      fn
        [
          ^expected_maximum_position_id,
          position_id
        ]
        when is_integer(position_id) ->
          :ok

        row ->
          raise """
          unexpected result row:

          #{inspect(row)}
          """
      end
    )

    ids =
      position_ids(rows)

    if ids != Enum.sort(ids) do
      raise """
      position IDs are not ordered
      """
    end

    if !Enum.all?(
         ids,
         fn id ->
           rem(
             id,
             selectivity
           ) == 0
         end
       ) do
      raise """
      result contains a position outside the benchmark
      pawn-structure neighborhood
      """
    end

    case {
      after_position_id,
      ids
    } do
      {
        nil,
        _ids
      } ->
        :ok

      {
        _after_position_id,
        []
      } ->
        :ok

      {
        after_position_id,
        [
          first_id
          | _remaining
        ]
      }
      when first_id >
             after_position_id ->
        :ok

      {
        after_position_id,
        [
          first_id
          | _remaining
        ]
      } ->
        raise """
        expected page to start after #{after_position_id},
        got #{first_id}
        """
    end

    rows
  end

  defp position_ids(rows) do
    Enum.map(
      rows,
      fn [
           _maximum_position_id,
           position_id
         ] ->
        position_id
      end
    )
  end

  defp validate_pair_plan!(page, plan) do
    if !String.contains?(
         plan,
         "using #{@pair_index}"
       ) do
      raise """
      production pair-relation #{page} plan did not use
      #{@pair_index}.

      Plan:

      #{plan}
      """
    end

    :ok
  end

  defp validate_packed_filter_plan!(page, plan) do
    if !String.contains?(
         plan,
         "positions_pkey on positions p"
       ) do
      raise """
      packed-filter #{page} plan did not scan positions
      through positions_pkey.

      The purpose of this benchmark is specifically to measure the
      ID-ordered primary-key scan chosen by PostgreSQL for the
      packed scalar-array predicate.

      Plan:

      #{plan}
      """
    end

    if String.contains?(
         plan,
         "using #{@pair_index} on positions p"
       ) do
      raise """
      packed-filter #{page} plan unexpectedly used
      #{@pair_index}.

      Plan:

      #{plan}
      """
    end

    if String.contains?(
         plan,
         @packed_expression_index
       ) do
      raise """
      packed-filter #{page} plan unexpectedly used the
      benchmark-only packed expression index.

      This benchmark must run with production indexes only.

      Plan:

      #{plan}
      """
    end

    if String.contains?(
         plan,
         @covering_id_index
       ) do
      raise """
      packed-filter #{page} plan unexpectedly used the
      benchmark-only covering ID index.

      This benchmark must run with production indexes only.

      Plan:

      #{plan}
      """
    end

    if String.contains?(
         plan,
         "Sort Key: p.id"
       ) do
      raise """
      packed-filter #{page} plan globally sorts p.id.

      The candidate is intended to preserve ID ordering directly
      from positions_pkey so LIMIT can terminate the scan early.

      Plan:

      #{plan}
      """
    end

    :ok
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

row_count =
  System.get_env(
    "PAWN_PACKED_FILTER_SELECTIVITY_BENCH_ROWS",
    "1000000"
  )
  |> String.to_integer()

selectivities =
  System.get_env(
    "PAWN_PACKED_FILTER_SELECTIVITY_BENCH_SELECTIVITIES",
    "150,200,300,500"
  )
  |> String.split(
    ",",
    trim: true
  )
  |> Enum.map(fn value ->
    value
    |> String.trim()
    |> String.to_integer()
  end)
  |> Enum.uniq()

page_size =
  System.get_env(
    "PAWN_PACKED_FILTER_SELECTIVITY_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if row_count <= 0 do
  raise """
  PAWN_PACKED_FILTER_SELECTIVITY_BENCH_ROWS must be positive
  """
end

if selectivities == [] do
  raise """
  PAWN_PACKED_FILTER_SELECTIVITY_BENCH_SELECTIVITIES must contain
  at least one positive integer
  """
end

if !Enum.all?(
     selectivities,
     &(&1 > 0)
   ) do
  raise """
  PAWN_PACKED_FILTER_SELECTIVITY_BENCH_SELECTIVITIES must contain
  only positive integers
  """
end

if page_size <= 0 do
  raise """
  PAWN_PACKED_FILTER_SELECTIVITY_BENCH_PAGE_SIZE must be positive
  """
end

Enum.each(
  selectivities,
  fn selectivity ->
    posting_count =
      div(
        row_count,
        selectivity
      )

    if posting_count <
         page_size * 2 do
      raise """
      selectivity 1/#{selectivity} yields only #{posting_count}
      matches in #{row_count} rows.

      Every configured selectivity must provide at least
      #{page_size * 2} matches so both benchmark pages are full.

      Increase PAWN_PACKED_FILTER_SELECTIVITY_BENCH_ROWS or remove
      that selectivity.
      """
    end
  end
)

try do
  Benchmark.cleanup()

  IO.puts("""
  Packed-filter selectivity benchmark

  rows per fixture:      #{row_count}
  selectivities:         #{Enum.map_join(selectivities, ", ", &"1/#{&1}")}
  neighborhood keys:     4_022
  page size:             #{page_size}

  This benchmark compares:

    * the currently compiled production pair-relation SQL

    * the packed scalar-array predicate that PostgreSQL previously
      executed as an ID-ordered positions_pkey scan

  There is deliberately no packed expression index and no covering
  ID index.

  The packed representation exists only in the query parameter and
  in the expression evaluated for candidate positions:

      int8send(white_pawns) || int8send(black_pawns)

  The 4,022 packed keys are prepared before timed SQL execution.

  The purpose of this benchmark is to find the selectivity range
  where early termination through ORDER BY p.id LIMIT is cheaper
  than probing the production pawn-structure index 4,022 times.

  No production schema survives this benchmark.
  """)

  Enum.each(
    selectivities,
    fn selectivity ->
      IO.puts("""

      ============================================================
      Building fixture for selectivity 1/#{selectivity}
      ============================================================
      """)

      fixture =
        Benchmark.build(
          row_count,
          selectivity
        )

      IO.puts("""
      rows:                  #{fixture.row_count}
      neighborhood matches:  #{fixture.posting_count}
      selectivity:           1/#{fixture.selectivity}
      positions table:       #{fixture.table_size} bytes
      positions primary key: #{fixture.primary_key_size} bytes
      pawn paging index:     #{fixture.pair_index_size} bytes
      record unique index:   #{fixture.record_index_size} bytes
      total positions size:  #{fixture.total_size} bytes
      """)

      Benchmark.benchmark(
        fixture,
        page_size
      )

      Benchmark.benchmark_bounded(
        fixture,
        page_size,
        [10_000, 15_000, 20_000]
      )
    end
  )
after
  Benchmark.cleanup()
end
