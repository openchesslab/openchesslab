alias Analysis.GameSearchPawnStructureSymmetryPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule Analysis.GameSearchPawnStructureSymmetryPostgresBenchmark do
  @moduledoc false

  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch.PostgresQuery
  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @positions_table "openchesslab_game_search_pawn_symmetry_positions"
  @occurrences_table "openchesslab_game_search_pawn_symmetry_occurrences"
  @records_table "openchesslab_game_search_pawn_symmetry_records"

  @positions_index "#{@positions_table}_paging_index"
  @occurrences_index "#{@occurrences_table}_position_id_id_index"
  @records_index "#{@records_table}_game_id_id_index"

  @source_structure %PawnStructure{
    white: 33_554_432,
    black: 35_184_372_088_832
  }

  def build(row_count, selectivity) do
    target_parameters =
      encoded_symmetry_parameters()

    drop_tables()

    setup_query!("""
    CREATE TABLE #{@positions_table} (
      id bigint PRIMARY KEY,
      white_pawns bigint NOT NULL,
      black_pawns bigint NOT NULL
    )
    """)

    setup_query!("""
    CREATE TABLE #{@occurrences_table} (
      id bigint PRIMARY KEY,
      game_id bigint NOT NULL,
      ply bigint NOT NULL,
      position_id bigint NOT NULL
    )
    """)

    setup_query!("""
    CREATE TABLE #{@records_table} (
      id bigint PRIMARY KEY,
      record_id text NOT NULL,
      game_id bigint NOT NULL,
      fullmove_number bigint NOT NULL,
      metadata jsonb NOT NULL
    )
    """)

    setup_query!(
      """
      INSERT INTO #{@positions_table} (
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
      ],
      timeout: :infinity
    )

    setup_query!(
      """
      INSERT INTO #{@occurrences_table} (
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
      [
        row_count
      ],
      timeout: :infinity
    )

    setup_query!(
      """
      INSERT INTO #{@records_table} (
        id,
        record_id,
        game_id,
        fullmove_number,
        metadata
      )
      SELECT
        id,
        id::text,
        id,
        1,
        '{}'::jsonb
      FROM generate_series(
        1::bigint,
        $1::bigint
      ) AS generated(id)
      """,
      [
        row_count
      ],
      timeout: :infinity
    )

    setup_query!("""
    CREATE INDEX #{@positions_index}
    ON #{@positions_table} (
      white_pawns,
      black_pawns,
      id
    )
    """)

    setup_query!("""
    CREATE INDEX #{@occurrences_index}
    ON #{@occurrences_table} (
      position_id,
      id
    )
    """)

    setup_query!("""
    CREATE INDEX #{@records_index}
    ON #{@records_table} (
      game_id,
      id
    )
    """)

    setup_query!("""
    ANALYZE
      #{@positions_table},
      #{@occurrences_table},
      #{@records_table}
    """)

    %{
      positions_size: total_relation_size(@positions_table),
      occurrences_size: total_relation_size(@occurrences_table),
      records_size: total_relation_size(@records_table)
    }
  end

  def benchmark(row_count, selectivity, page_size) do
    generic_query =
      generic_or_query()

    specialized_query =
      specialized_query()

    {
      generic_first_sql,
      generic_first_parameters
    } =
      compile_first!(
        generic_query,
        page_size
      )

    {
      specialized_first_sql,
      specialized_first_parameters
    } =
      compile_first!(
        specialized_query,
        page_size
      )

    validate_compiler_shapes!(
      generic_first_sql,
      specialized_first_sql
    )

    generic_first_rows =
      query_rows(
        generic_first_sql,
        generic_first_parameters
      )

    specialized_first_rows =
      query_rows(
        specialized_first_sql,
        specialized_first_parameters
      )

    assert_same_rows!(
      "first page",
      generic_first_rows,
      specialized_first_rows
    )

    validate_page!(
      generic_first_rows,
      row_count,
      page_size,
      selectivity
    )

    cursor =
      cursor_from_rows(generic_first_rows)

    {
      generic_next_sql,
      generic_next_parameters
    } =
      compile_next!(
        generic_query,
        cursor,
        page_size
      )

    {
      specialized_next_sql,
      specialized_next_parameters
    } =
      compile_next!(
        specialized_query,
        cursor,
        page_size
      )

    validate_compiler_shapes!(
      generic_next_sql,
      specialized_next_sql
    )

    validate_specialized_next_bounds!(specialized_next_sql)

    generic_second_rows =
      query_rows(
        generic_next_sql,
        generic_next_parameters
      )

    specialized_second_rows =
      query_rows(
        specialized_next_sql,
        specialized_next_parameters
      )

    assert_same_rows!(
      "second page",
      generic_second_rows,
      specialized_second_rows
    )

    validate_page!(
      generic_second_rows,
      row_count,
      page_size,
      selectivity
    )

    IO.puts("""
    Generic OR production compiler route

    First-page plan:
    #{explain(generic_first_sql,
    generic_first_parameters)}

    Second-page plan:
    #{explain(generic_next_sql,
    generic_next_parameters)}

    Specialized symmetry production compiler route

    First-page plan:
    #{explain(specialized_first_sql,
    specialized_first_parameters)}

    Second-page plan:
    #{explain(specialized_next_sql,
    specialized_next_parameters)}
    """)

    Benchee.run(
      %{
        "game search generic OR compiler: first page" => fn ->
          generic_first_sql
          |> query_rows(generic_first_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search generic OR compiler: second page" => fn ->
          generic_next_sql
          |> query_rows(generic_next_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search specialized symmetry compiler: first page" => fn ->
          specialized_first_sql
          |> query_rows(specialized_first_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search specialized symmetry compiler: second page" => fn ->
          specialized_next_sql
          |> query_rows(specialized_next_parameters)
          |> validate_page!(
            row_count,
            page_size,
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
    drop_tables()
  end

  defp generic_or_query do
    @source_structure
    |> PawnStructure.symmetries()
    |> Enum.map(&PositionQuery.pawn_structure/1)
    |> PositionQuery.any()
  end

  defp specialized_query do
    PositionQuery.pawn_structure_symmetries(@source_structure)
  end

  defp compile_first!(query, page_size) do
    case PostgresQuery.compile_first(
           query,
           GameRecordQuery.match_all(),
           page_size
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          benchmark_relations(sql),
          parameters
        }

      {:error, reason} ->
        raise """
        could not compile first-page game search:

        #{inspect(reason)}
        """
    end
  end

  defp compile_next!(query, cursor, page_size) do
    case PostgresQuery.compile_next(
           query,
           GameRecordQuery.match_all(),
           cursor.maximum_position_id,
           cursor.maximum_occurrence_id,
           cursor.maximum_record_row_id,
           cursor.last_position_id,
           cursor.last_occurrence_id,
           cursor.last_record_row_id,
           page_size
         ) do
      {
        :ok,
        sql,
        parameters
      } ->
        {
          benchmark_relations(sql),
          parameters
        }

      {:error, reason} ->
        raise """
        could not compile second-page game search:

        #{inspect(reason)}
        """
    end
  end

  defp encoded_symmetry_parameters do
    structures =
      PawnStructure.symmetries(@source_structure)

    if length(structures) != 4 do
      raise """
      benchmark source structure must have exactly four distinct symmetries,
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

  defp validate_compiler_shapes!(generic_sql, specialized_sql) do
    normalized_generic =
      normalize_sql(generic_sql)

    normalized_specialized =
      normalize_sql(specialized_sql)

    if String.contains?(
         normalized_generic,
         "UNION ALL"
       ) do
      raise """
      generic OR compiler unexpectedly produced UNION ALL
      """
    end

    if occurrences(
         normalized_specialized,
         "UNION ALL"
       ) != 3 do
      raise """
      specialized symmetry compiler did not produce four ordered branches
      """
    end

    if String.contains?(
         normalized_specialized,
         " OR "
       ) do
      raise """
      specialized symmetry compiler unexpectedly produced OR
      """
    end

    if occurrences(
         normalized_specialized,
         "ORDER BY p.id"
       ) != 4 do
      raise """
      specialized symmetry compiler did not order every symmetry branch by id
      """
    end
  end

  defp validate_specialized_next_bounds!(sql) do
    normalized_sql =
      normalize_sql(sql)

    if occurrences(
         normalized_sql,
         "p.id >="
       ) != 4 do
      raise """
      specialized game-search compiler did not keep the cursor position
      in every symmetry branch
      """
    end

    if occurrences(
         normalized_sql,
         "p.id <="
       ) != 4 do
      raise """
      specialized game-search compiler did not push the high-water mark
      into every symmetry branch
      """
    end
  end

  defp benchmark_relations(sql) do
    rewritten =
      sql
      |> String.replace(
        "positions",
        @positions_table
      )
      |> String.replace(
        "game_occurrences",
        @occurrences_table
      )
      |> String.replace(
        "game_records",
        @records_table
      )

    if rewritten == sql do
      raise """
      compiled game-search query did not reference the expected relations
      """
    end

    rewritten
  end

  defp cursor_from_rows(rows) do
    case List.last(rows) do
      [
        maximum_position_id,
        maximum_occurrence_id,
        maximum_record_row_id,
        position_id,
        occurrence_id,
        _occurrence_game_id,
        _ply,
        record_row_id,
        _record_id,
        _record_game_id,
        _fullmove_number,
        _metadata
      ] ->
        %{
          maximum_position_id: maximum_position_id,
          maximum_occurrence_id: maximum_occurrence_id,
          maximum_record_row_id: maximum_record_row_id,
          last_position_id: position_id,
          last_occurrence_id: occurrence_id,
          last_record_row_id: record_row_id
        }

      nil ->
        raise """
        benchmark first page was empty
        """
    end
  end

  defp assert_same_rows!(page, generic_rows, specialized_rows) do
    if generic_rows !=
         specialized_rows do
      raise """
      generic OR and specialized symmetry compiler returned different #{page}.

      Generic:
      #{inspect(generic_rows)}

      Specialized:
      #{inspect(specialized_rows)}
      """
    end
  end

  defp validate_page!(rows, expected_maximum_id, expected_count, selectivity) do
    if length(rows) !=
         expected_count do
      raise """
      expected #{expected_count} rows,
      got #{length(rows)}
      """
    end

    triples =
      Enum.map(
        rows,
        fn
          [
            maximum_position_id,
            maximum_occurrence_id,
            maximum_record_row_id,
            position_id,
            occurrence_id,
            _occurrence_game_id,
            _ply,
            record_row_id,
            _record_id,
            _record_game_id,
            _fullmove_number,
            _metadata
          ] ->
            if maximum_position_id !=
                 expected_maximum_id or
                 maximum_occurrence_id !=
                   expected_maximum_id or
                 maximum_record_row_id !=
                   expected_maximum_id do
              raise """
              unexpected high-water marks:
              #{inspect({maximum_position_id, maximum_occurrence_id, maximum_record_row_id})}
              """
            end

            if rem(
                 position_id,
                 selectivity
               ) != 0 do
              raise """
              position #{position_id} is outside the symmetry fixture
              """
            end

            {
              position_id,
              occurrence_id,
              record_row_id
            }
        end
      )

    if triples !=
         Enum.sort(triples) do
      raise """
      result page is not ordered by
      position id, occurrence id and record id
      """
    end

    rows
  end

  defp query_rows(sql, parameters) do
    SQL.query!(
      Repo,
      sql,
      parameters
    ).rows
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

  defp setup_query!(sql, parameters \\ [], options \\ []) do
    SQL.query!(
      Repo,
      sql,
      parameters,
      options
    )
  end

  defp drop_tables do
    setup_query!("DROP TABLE IF EXISTS #{@records_table}")

    setup_query!("DROP TABLE IF EXISTS #{@occurrences_table}")

    setup_query!("DROP TABLE IF EXISTS #{@positions_table}")
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

row_count =
  System.get_env(
    "GAME_SEARCH_PAWN_SYMMETRY_BENCH_ROWS",
    "1000000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "GAME_SEARCH_PAWN_SYMMETRY_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "GAME_SEARCH_PAWN_SYMMETRY_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if row_count <= 0 do
  raise """
  GAME_SEARCH_PAWN_SYMMETRY_BENCH_ROWS must be positive
  """
end

if selectivity <= 0 do
  raise """
  GAME_SEARCH_PAWN_SYMMETRY_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  GAME_SEARCH_PAWN_SYMMETRY_BENCH_PAGE_SIZE must be positive
  """
end

available_matches =
  div(
    row_count,
    selectivity
  )

if available_matches <
     page_size * 2 do
  raise """
  benchmark needs at least two full result pages.

  Available symmetry matches: #{available_matches}
  Required: #{page_size * 2}
  """
end

try do
  IO.puts("""
  Building PostgreSQL game-search pawn-symmetry benchmark fixture...

  rows per relation: #{row_count}
  symmetry matches:  #{available_matches}
  selectivity:       1/#{selectivity}
  symmetry keys:     4
  page size:         #{page_size}
  """)

  fixture =
    Benchmark.build(
      row_count,
      selectivity
    )

  IO.puts("""
  PostgreSQL production-compiler game-search pawn-symmetry benchmark

  positions total size:   #{fixture.positions_size} bytes
  occurrences total size: #{fixture.occurrences_size} bytes
  records total size:     #{fixture.records_size} bytes

  Comparing the generic OR compiler route with the specialized
  pawn-structure symmetry compiler route.
  """)

  Benchmark.benchmark(
    row_count,
    selectivity,
    page_size
  )
after
  Benchmark.cleanup()
end
