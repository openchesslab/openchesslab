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

  @candidate_first_sql """
  SELECT
    COALESCE(
      (
        SELECT max(id)
        FROM #{@positions_table}
      ),
      0
    )::bigint AS maximum_position_id,
    COALESCE(
      (
        SELECT max(id)
        FROM #{@occurrences_table}
      ),
      0
    )::bigint AS maximum_occurrence_id,
    COALESCE(
      (
        SELECT max(id)
        FROM #{@records_table}
      ),
      0
    )::bigint AS maximum_record_row_id,
    matches.id,
    go.id,
    go.game_id,
    go.ply,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM (
    (
      SELECT
        p.id
      FROM #{@positions_table} AS p
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
      FROM #{@positions_table} AS p
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
      FROM #{@positions_table} AS p
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
      FROM #{@positions_table} AS p
      WHERE
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
      ORDER BY
        p.id
    )
  ) AS matches
  JOIN #{@occurrences_table} AS go
    ON go.position_id = matches.id
  JOIN #{@records_table} AS gr
    ON gr.game_id = go.game_id
  ORDER BY
    matches.id,
    go.id,
    gr.id
  LIMIT $9::bigint
  """

  @candidate_next_sql """
  SELECT
    $9::bigint AS maximum_position_id,
    $10::bigint AS maximum_occurrence_id,
    $11::bigint AS maximum_record_row_id,
    matches.id,
    go.id,
    go.game_id,
    go.ply,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM (
    (
      SELECT
        p.id
      FROM #{@positions_table} AS p
      WHERE
        p.white_pawns = $1::bigint
        AND p.black_pawns = $2::bigint
        AND p.id >= $12::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@positions_table} AS p
      WHERE
        p.white_pawns = $3::bigint
        AND p.black_pawns = $4::bigint
        AND p.id >= $12::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@positions_table} AS p
      WHERE
        p.white_pawns = $5::bigint
        AND p.black_pawns = $6::bigint
        AND p.id >= $12::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )

    UNION ALL

    (
      SELECT
        p.id
      FROM #{@positions_table} AS p
      WHERE
        p.white_pawns = $7::bigint
        AND p.black_pawns = $8::bigint
        AND p.id >= $12::bigint
        AND p.id <= $9::bigint
      ORDER BY
        p.id
    )
  ) AS matches
  JOIN #{@occurrences_table} AS go
    ON go.position_id = matches.id
  JOIN #{@records_table} AS gr
    ON gr.game_id = go.game_id
  WHERE
    go.position_id <= $9::bigint
    AND go.id <= $10::bigint
    AND gr.id <= $11::bigint
    AND (
      go.position_id,
      go.id
    ) >= (
      $12::bigint,
      $13::bigint
    )
    AND (
      go.position_id,
      go.id,
      gr.id
    ) > (
      $12::bigint,
      $13::bigint,
      $14::bigint
    )
  ORDER BY
    matches.id,
    go.id,
    gr.id
  LIMIT $15::bigint
  """

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
    symmetry_parameters =
      encoded_symmetry_parameters()

    {
      generic_first_sql,
      generic_first_parameters
    } =
      generic_first_sql(page_size)

    candidate_first_parameters =
      symmetry_parameters ++
        [
          page_size
        ]

    generic_first_rows =
      query_rows(
        generic_first_sql,
        generic_first_parameters
      )

    candidate_first_rows =
      query_rows(
        @candidate_first_sql,
        candidate_first_parameters
      )

    assert_same_rows!(
      "first page",
      generic_first_rows,
      candidate_first_rows
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
      generic_next_sql(
        cursor,
        page_size
      )

    candidate_next_parameters =
      symmetry_parameters ++
        [
          cursor.maximum_position_id,
          cursor.maximum_occurrence_id,
          cursor.maximum_record_row_id,
          cursor.last_position_id,
          cursor.last_occurrence_id,
          cursor.last_record_row_id,
          page_size
        ]

    generic_second_rows =
      query_rows(
        generic_next_sql,
        generic_next_parameters
      )

    candidate_second_rows =
      query_rows(
        @candidate_next_sql,
        candidate_next_parameters
      )

    assert_same_rows!(
      "second page",
      generic_second_rows,
      candidate_second_rows
    )

    validate_page!(
      generic_second_rows,
      row_count,
      page_size,
      selectivity
    )

    IO.puts("""
    Current generic OR game-search route

    First-page plan:
    #{explain(generic_first_sql,
    generic_first_parameters)}

    Second-page plan:
    #{explain(generic_next_sql,
    generic_next_parameters)}

    Candidate ordered UNION ALL game-search route

    First-page plan:
    #{explain(@candidate_first_sql,
    candidate_first_parameters)}

    Second-page plan:
    #{explain(@candidate_next_sql,
    candidate_next_parameters)}
    """)

    Benchee.run(
      %{
        "game search generic OR: first page" => fn ->
          generic_first_sql
          |> query_rows(generic_first_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search generic OR: second page" => fn ->
          generic_next_sql
          |> query_rows(generic_next_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search ordered UNION ALL: first page" => fn ->
          @candidate_first_sql
          |> query_rows(candidate_first_parameters)
          |> validate_page!(
            row_count,
            page_size,
            selectivity
          )
        end,
        "game search ordered UNION ALL: second page" => fn ->
          @candidate_next_sql
          |> query_rows(candidate_next_parameters)
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

  defp generic_first_sql(page_size) do
    case PostgresQuery.compile_first(
           generic_or_query(),
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
        could not compile generic first-page game search:

        #{inspect(reason)}
        """
    end
  end

  defp generic_next_sql(cursor, page_size) do
    case PostgresQuery.compile_next(
           generic_or_query(),
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
        could not compile generic second-page game search:

        #{inspect(reason)}
        """
    end
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

  defp assert_same_rows!(page, generic_rows, candidate_rows) do
    if generic_rows !=
         candidate_rows do
      raise """
      generic OR and candidate UNION ALL returned different #{page}.

      Generic:
      #{inspect(generic_rows)}

      Candidate:
      #{inspect(candidate_rows)}
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

if available_matches < page_size * 2 do
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
  PostgreSQL game-search pawn-symmetry benchmark

  positions total size:   #{fixture.positions_size} bytes
  occurrences total size: #{fixture.occurrences_size} bytes
  records total size:     #{fixture.records_size} bytes

  Comparing the current generic OR game-search compiler route with
  an ordered UNION ALL position source before the occurrence and
  record joins.
  """)

  Benchmark.benchmark(
    row_count,
    selectivity,
    page_size
  )
after
  Benchmark.cleanup()
end
