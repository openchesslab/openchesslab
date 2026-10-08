alias OpenChessLab.Database.PawnStructureEditNeighborhoodPackedExpressionProductionPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditNeighborhoodPackedExpressionProductionPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @pair_index "positions_pawn_structure_index"
  @packed_index "positions_pawn_structure_packed_bench_index"
  @record_index "positions_record_unique"

  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_keys 4_022

  def build(posting_count, selectivity) do
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

    validate_packed_encoding!(
      hd(encoded_structures),
      hd(packed_keys)
    )

    row_count =
      posting_count * selectivity

    cleanup()
    clear_positions()
    create_packed_index()

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
      packed_keys: packed_keys,
      table_size: relation_size("positions"),
      pair_index_size: relation_size(@pair_index),
      packed_index_size: relation_size(@packed_index),
      record_index_size: relation_size(@record_index),
      total_size: total_relation_size("positions")
    }
  end

  def benchmark(
        %{query: query, row_count: row_count, packed_keys: packed_keys},
        posting_count,
        selectivity,
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
      min(posting_count, requested_rows),
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

    validate_packed_plan!(
      :first_page,
      packed_first_plan
    )

    validate_packed_plan!(
      :second_page,
      packed_second_plan
    )

    IO.puts("""
    PostgreSQL server version:
    #{server_version()}

    Production pair index:
    #{index_definition(@pair_index)}

    Benchmark-only packed expression index:
    #{index_definition(@packed_index)}

    Current production pair-relation first-page plan:
    #{pair_first_plan}

    Packed expression first-page plan:
    #{packed_first_plan}

    Current production pair-relation second-page plan:
    #{pair_second_plan}

    Packed expression second-page plan:
    #{packed_second_plan}
    """)

    Benchee.run(
      %{
        "production pair relation: first page" => fn ->
          pair_first_sql
          |> query_rows(pair_first_parameters)
          |> validate_rows!(
            row_count,
            min(posting_count, requested_rows),
            selectivity,
            nil
          )
        end,
        "packed expression: first page" => fn ->
          packed_first_sql
          |> query_rows(packed_first_parameters)
          |> validate_rows!(
            row_count,
            min(posting_count, requested_rows),
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
        "packed expression: second page" => fn ->
          packed_second_sql
          |> query_rows(packed_second_parameters)
          |> validate_rows!(
            row_count,
            expected_second_count,
            selectivity,
            last_position_id
          )
        end,
        "pack 4,022 neighborhood keys" => fn ->
          query
          |> neighborhood_structures!()
          |> Enum.map(fn structure ->
            structure
            |> encode_structure!()
            |> pack_encoded_structure()
          end)
          |> validate_packed_keys!()
        end
      },
      warmup: 1,
      time: 3,
      parallel: 1
    )
  end

  def cleanup do
    setup_query!("DROP INDEX IF EXISTS #{@packed_index}")
  end

  defp create_packed_index do
    setup_query!("""
    CREATE INDEX #{@packed_index}
    ON positions (
      (
        int8send(white_pawns) ||
          int8send(black_pawns)
      ),
      id
    )
    """)
  end

  defp compile_pair_first!(query, requested_rows) do
    case PostgresPage.compile_first(
           query,
           requested_rows
         ) do
      {:ok, sql, parameters} ->
        {sql, parameters}

      {:error, reason} ->
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
      {:ok, sql, parameters} ->
        {sql, parameters}

      {:error, reason} ->
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

  defp neighborhood_structures!({:pawn_structure_edit_neighborhood, structures}) do
    if length(structures) != @expected_keys do
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
      {:ok, encoded_structure} ->
        encoded_structure

      {:error, reason} ->
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

  defp validate_packed_encoding!({white_pawns, black_pawns}, packed_key) do
    case SQL.query!(
           Repo,
           """
           SELECT
             int8send($1::bigint) ||
               int8send($2::bigint) =
               $3::bytea
           """,
           [
             white_pawns,
             black_pawns,
             packed_key
           ]
         ).rows do
      [[true]] ->
        :ok

      result ->
        raise """
        Elixir packed pawn-structure encoding does not match
        PostgreSQL int8send representation:

        #{inspect(result)}
        """
    end
  end

  defp validate_packed_keys!(packed_keys) do
    if length(packed_keys) != @expected_keys do
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
      packed expression results differ from the production
      pair-relation results for #{page}.

      Production pair relation:
      #{inspect(pair_rows)}

      Packed expression:
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
    if length(rows) != expected_count do
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
           rem(id, selectivity) == 0
         end
       ) do
      raise """
      result contains a position outside the benchmark
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

  defp validate_packed_plan!(page, plan) do
    planner_used_id_order? =
      String.contains?(
        plan,
        "positions_pkey on positions p"
      )

    planner_used_packed_index? =
      String.contains?(
        plan,
        @packed_index
      )

    if !planner_used_id_order? &&
         !planner_used_packed_index? do
      raise """
      packed #{page} plan used neither the ID-ordered positions
      primary-key scan nor the packed expression index.

      Plan:

      #{plan}
      """
    end

    if String.contains?(
         plan,
         @pair_index
       ) do
      raise """
      packed #{page} plan unexpectedly used #{@pair_index}.

      The packed scalar-array query must remain independent of the
      production pair index.

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

posting_count =
  System.get_env(
    "PAWN_PACKED_PRODUCTION_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_PACKED_PRODUCTION_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_PACKED_PRODUCTION_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_PACKED_PRODUCTION_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_PACKED_PRODUCTION_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_PACKED_PRODUCTION_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count < page_size * 2 do
  raise """
  PAWN_PACKED_PRODUCTION_BENCH_POSTINGS must be at least twice
  PAWN_PACKED_PRODUCTION_BENCH_PAGE_SIZE so the benchmark has a
  full second page.
  """
end

try do
  IO.puts("""
  Building production packed-expression pawn-neighborhood fixture...

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
  Production packed-expression pawn-neighborhood benchmark

  rows:                    #{fixture.row_count}
  positions table:         #{fixture.table_size} bytes
  pair index:              #{fixture.pair_index_size} bytes
  packed expression index: #{fixture.packed_index_size} bytes
  record unique index:     #{fixture.record_index_size} bytes
  total positions size:    #{fixture.total_size} bytes

  Both pawn-structure indexes existed before the benchmark rows
  were inserted.

  This means the pair index and packed expression index see the
  same insertion pattern and the resulting index sizes are directly
  comparable for this fixture.

  The packed key is not stored in positions. It exists only as the
  exact, collision-free 128-bit expression:

      int8send(white_pawns) || int8send(black_pawns)

  The benchmark compares:

    * the currently compiled production pair-relation SQL
    * equivalent packed scalar-array SQL on the real positions table
    * application-side packing of all 4,022 neighborhood keys

  No production schema survives this benchmark.
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
