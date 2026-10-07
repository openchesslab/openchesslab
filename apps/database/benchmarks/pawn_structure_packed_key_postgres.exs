alias OpenChessLab.Database.PawnStructurePackedKeyPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructurePackedKeyPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @table "pawn_structure_packed_key_bench_positions"
  @pair_index "pawn_structure_packed_key_bench_pair_index"
  @packed_index "pawn_structure_packed_key_bench_packed_index"

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

    {
      white_keys,
      black_keys
    } =
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
      posting_count *
        selectivity

    cleanup()

    setup_query!("""
    CREATE UNLOGGED TABLE #{@table} (
      id bigint NOT NULL,
      white_pawns bigint NOT NULL,
      black_pawns bigint NOT NULL,
      pawn_structure_key bytea NOT NULL
    )
    """)

    setup_query!(
      """
      WITH generated_positions AS (
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
          END AS white_pawns,
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
          END AS black_pawns
        FROM generate_series(
          1::bigint,
          $1::bigint
        ) AS generated(id)
      )
      INSERT INTO #{@table} (
        id,
        white_pawns,
        black_pawns,
        pawn_structure_key
      )
      SELECT
        id,
        white_pawns,
        black_pawns,
        int8send(white_pawns) ||
          int8send(black_pawns)
      FROM generated_positions
      """,
      [
        row_count,
        selectivity,
        white_keys,
        black_keys
      ]
    )

    setup_query!("""
    CREATE INDEX #{@pair_index}
    ON #{@table} (
      white_pawns,
      black_pawns,
      id
    )
    """)

    setup_query!("""
    CREATE INDEX #{@packed_index}
    ON #{@table} (
      pawn_structure_key,
      id
    )
    """)

    setup_query!("VACUUM (ANALYZE) #{@table}")

    %{
      row_count: row_count,
      structure_count: structure_count,
      white_keys: white_keys,
      black_keys: black_keys,
      packed_keys: packed_keys,
      table_size: relation_size(@table),
      pair_index_size: relation_size(@pair_index),
      packed_index_size: relation_size(@packed_index)
    }
  end

  def benchmark(
        %{
          row_count: row_count,
          white_keys: white_keys,
          black_keys: black_keys,
          packed_keys: packed_keys
        },
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

    packed_first_sql =
      packed_first_sql()

    packed_first_parameters = [
      packed_keys,
      requested_rows
    ]

    pair_first_ids =
      query_ids(
        pair_first_sql,
        pair_first_parameters
      )

    packed_first_ids =
      query_ids(
        packed_first_sql,
        packed_first_parameters
      )

    validate_equal_results!(
      :first_page,
      pair_first_ids,
      packed_first_ids
    )

    validate_ids!(
      pair_first_ids,
      min(
        posting_count,
        requested_rows
      ),
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

    packed_second_sql =
      packed_second_sql()

    packed_second_parameters = [
      packed_keys,
      last_position_id,
      row_count,
      requested_rows
    ]

    pair_second_ids =
      query_ids(
        pair_second_sql,
        pair_second_parameters
      )

    packed_second_ids =
      query_ids(
        packed_second_sql,
        packed_second_parameters
      )

    validate_equal_results!(
      :second_page,
      pair_second_ids,
      packed_second_ids
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

    Current pair-relation first-page plan:
    #{explain(pair_first_sql, pair_first_parameters)}

    Packed scalar-array first-page plan:
    #{explain(packed_first_sql, packed_first_parameters)}

    Current pair-relation second-page plan:
    #{explain(pair_second_sql, pair_second_parameters)}

    Packed scalar-array second-page plan:
    #{explain(packed_second_sql, packed_second_parameters)}
    """)

    Benchee.run(
      %{
        "pair relation: first page" => fn ->
          pair_first_sql
          |> query_ids(pair_first_parameters)
          |> validate_ids!(
            min(
              posting_count,
              requested_rows
            ),
            selectivity,
            nil
          )
        end,
        "packed scalar-array: first page" => fn ->
          packed_first_sql
          |> query_ids(packed_first_parameters)
          |> validate_ids!(
            min(
              posting_count,
              requested_rows
            ),
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
        "packed scalar-array: second page" => fn ->
          packed_second_sql
          |> query_ids(packed_second_parameters)
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

  def cleanup do
    setup_query!("DROP TABLE IF EXISTS #{@table}")
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
    JOIN #{@table} AS p
      ON p.white_pawns =
        pawn_structure_keys.white_pawns
      AND p.black_pawns =
        pawn_structure_keys.black_pawns
    ORDER BY
      p.id
    LIMIT $3::bigint
    """
  end

  defp packed_first_sql do
    """
    SELECT
      p.id
    FROM #{@table} AS p
    WHERE
      p.pawn_structure_key =
        ANY($1::bytea[])
    ORDER BY
      p.id
    LIMIT $2::bigint
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
    JOIN #{@table} AS p
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

  defp packed_second_sql do
    """
    SELECT
      p.id
    FROM #{@table} AS p
    WHERE
      p.pawn_structure_key =
        ANY($1::bytea[])
      AND p.id > $2::bigint
      AND p.id <= $3::bigint
    ORDER BY
      p.id
    LIMIT $4::bigint
    """
  end

  defp encoded_distance_two_structures do
    structures =
      EditDistance.neighborhood(
        @source_structure,
        2
      )

    if length(structures) !=
         @expected_keys do
      raise """
      expected #{@expected_keys} distance-2 pawn-structure keys,
      got #{length(structures)}
      """
    end

    Enum.map(
      structures,
      fn structure ->
        case PositionPawnStructureCodec.encode(structure) do
          {
            :ok,
            encoded_structure
          } ->
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
      [
        [
          true
        ]
      ] ->
        :ok

      result ->
        raise """
        Elixir packed pawn-structure encoding does not match
        PostgreSQL int8send representation:

        #{inspect(result)}
        """
    end
  end

  defp query_ids(sql, parameters) do
    Repo
    |> SQL.query!(
      sql,
      parameters
    )
    |> Map.fetch!(:rows)
    |> Enum.map(fn
      [
        id
      ] ->
        id
    end)
  end

  defp validate_equal_results!(page, pair_ids, packed_ids) do
    if pair_ids !=
         packed_ids do
      raise """
      packed scalar-array results differ from the current
      pair-relation results for #{page}.

      Pair relation:
      #{inspect(pair_ids)}

      Packed scalar-array:
      #{inspect(packed_ids)}
      """
    end

    :ok
  end

  defp validate_ids!(ids, expected_count, selectivity, after_position_id) do
    if length(ids) !=
         expected_count do
      raise """
      expected #{expected_count} result rows,
      got #{length(ids)}
      """
    end

    if ids !=
         Enum.sort(ids) do
      raise """
      result IDs are not ordered
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
      result contains a row outside the benchmark
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

  defp server_version do
    case SQL.query!(
           Repo,
           "SHOW server_version",
           []
         ).rows do
      [
        [
          version
        ]
      ] ->
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
    "PAWN_PACKED_KEY_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_PACKED_KEY_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_PACKED_KEY_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_PACKED_KEY_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_PACKED_KEY_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_PACKED_KEY_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count <
     page_size * 2 do
  raise """
  PAWN_PACKED_KEY_BENCH_POSTINGS must be at least twice
  PAWN_PACKED_KEY_BENCH_PAGE_SIZE so the benchmark has a
  full second page.
  """
end

try do
  IO.puts("""
  Building packed pawn-structure key benchmark fixture...

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
  Packed pawn-structure key paging benchmark

  rows:                  #{fixture.row_count}
  table size:            #{fixture.table_size} bytes
  pair index size:       #{fixture.pair_index_size} bytes
  packed index size:     #{fixture.packed_index_size} bytes
  neighborhood keys:     #{fixture.structure_count}

  This compares two exact, collision-free representations over the
  same rows:

    * the current two-bigint key relation joined through
      (white_pawns, black_pawns, id)
    * one packed 128-bit key searched with = ANY(bytea[]) through
      (pawn_structure_key, id)

  The packed bytea representation is benchmark-only. This experiment
  tests PostgreSQL's native B-tree scalar-array scan strategy before
  making any production schema decision.
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
