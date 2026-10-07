alias OpenChessLab.Database.PawnStructureEditNeighborhoodProductionPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditNeighborhoodProductionPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Analysis.PositionStore
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @pawn_structure_index "positions_pawn_structure_index"
  @record_index "positions_record_unique"

  # White:
  #   a3 b4 c4 d4 e2 f2 g2 h3
  #
  # Black:
  #   a6 b7 c6 d6 e6 f5 g5 h6
  #
  # Under the current elementary edit vocabulary this structure has:
  #
  #   * 92 distinct distance-one neighbors
  #   * 4,022 distinct structures within distance <= 2
  #
  # This benchmark deliberately uses the real `positions` relation,
  # production indexes, PostgresPage compiler and PositionStore paging.
  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_distance_one_neighbors 92
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
      Enum.unzip(encoded_structures)

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
      [
        row_count
      ]
    )

    setup_query!("ANALYZE positions")

    %{
      row_count: row_count,
      structure_count: structure_count,
      table_size: relation_size("positions"),
      pawn_index_size: relation_size(@pawn_structure_index),
      record_index_size: relation_size(@record_index),
      total_size: total_relation_size("positions")
    }
  end

  def benchmark(posting_count, selectivity, page_size, row_count) do
    query =
      edit_query()

    assert_query_size!(query)

    requested_rows =
      page_size + 1

    {
      first_sql,
      first_parameters
    } =
      compile_first!(
        query,
        requested_rows
      )

    validate_first_sql!(first_sql)

    first_rows =
      query_rows(
        first_sql,
        first_parameters
      )

    expected_first_compiled_count =
      min(
        posting_count,
        requested_rows
      )

    validate_compiled_rows!(
      first_rows,
      row_count,
      expected_first_compiled_count,
      selectivity,
      nil
    )

    first_page =
      position_store_page!(
        query,
        limit: page_size
      )

    validate_position_store_page!(
      first_page,
      min(
        posting_count,
        page_size
      ),
      selectivity,
      nil
    )

    first_cursor =
      first_page.next ||
        raise """
        expected first PositionStore page to have a cursor
        """

    last_position_id =
      first_page.entries
      |> List.last()

    expected_first_page_entries =
      Enum.take(
        compiled_position_ids(first_rows),
        page_size
      )

    if expected_first_page_entries !=
         first_page.entries do
      raise """
      compiled first page and PositionStore first page differ.

      Compiled:
      #{inspect(expected_first_page_entries)}

      PositionStore:
      #{inspect(first_page.entries)}
      """
    end

    {
      second_sql,
      second_parameters
    } =
      compile_next!(
        query,
        row_count,
        last_position_id,
        requested_rows
      )

    validate_second_sql!(second_sql)

    second_rows =
      query_rows(
        second_sql,
        second_parameters
      )

    expected_second_compiled_count =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(requested_rows)

    validate_compiled_rows!(
      second_rows,
      row_count,
      expected_second_compiled_count,
      selectivity,
      last_position_id
    )

    second_page =
      position_store_page!(
        query,
        limit: page_size,
        cursor: first_cursor
      )

    expected_second_page_count =
      posting_count
      |> Kernel.-(page_size)
      |> max(0)
      |> min(page_size)

    validate_position_store_page!(
      second_page,
      expected_second_page_count,
      selectivity,
      last_position_id
    )

    expected_second_page_entries =
      Enum.take(
        compiled_position_ids(second_rows),
        page_size
      )

    if expected_second_page_entries !=
         second_page.entries do
      raise """
      compiled second page and PositionStore second page differ.

      Compiled:
      #{inspect(expected_second_page_entries)}

      PositionStore:
      #{inspect(second_page.entries)}
      """
    end

    IO.puts("""
    Production PostgresPage compiler

    First-page plan:
    #{explain(first_sql,
    first_parameters)}

    Second-page plan:
    #{explain(second_sql,
    second_parameters)}
    """)

    Benchee.run(
      %{
        "compiled SQL: first page" => fn ->
          first_sql
          |> query_rows(first_parameters)
          |> validate_compiled_rows!(
            row_count,
            expected_first_compiled_count,
            selectivity,
            nil
          )
        end,
        "compiled SQL: second page" => fn ->
          second_sql
          |> query_rows(second_parameters)
          |> validate_compiled_rows!(
            row_count,
            expected_second_compiled_count,
            selectivity,
            last_position_id
          )
        end,
        "PositionStore: first page" => fn ->
          query
          |> position_store_page!(limit: page_size)
          |> validate_position_store_page!(
            min(
              posting_count,
              page_size
            ),
            selectivity,
            nil
          )
        end,
        "PositionStore: second page" => fn ->
          query
          |> position_store_page!(
            limit: page_size,
            cursor: first_cursor
          )
          |> validate_position_store_page!(
            expected_second_page_count,
            selectivity,
            last_position_id
          )
        end,
        "distance-2 query construction" => fn ->
          @source_structure
          |> PositionQuery.pawn_structure_edit_neighborhood(2)
          |> assert_query_size!()
        end
      },
      warmup: 1,
      time: 3,
      parallel: 1
    )
  end

  def cleanup do
    clear_positions()
  end

  defp edit_query do
    PositionQuery.pawn_structure_edit_neighborhood(
      @source_structure,
      2
    )
  end

  defp assert_query_size!({:pawn_structure_edit_neighborhood, structures} = query) do
    if length(structures) !=
         @expected_distance_two_keys do
      raise """
      expected #{@expected_distance_two_keys} structures in the
      production edit-neighborhood query, got #{length(structures)}
      """
    end

    query
  end

  defp assert_query_size!(query) do
    raise """
    expected a pawn-structure edit-neighborhood query, got:

    #{inspect(query)}
    """
  end

  defp compile_first!(query, requested_rows) do
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

      {:error, reason} ->
        raise """
        could not compile production first page:

        #{inspect(reason)}
        """
    end
  end

  defp compile_next!(query, maximum_position_id, last_position_id, requested_rows) do
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

      {:error, reason} ->
        raise """
        could not compile production second page:

        #{inspect(reason)}
        """
    end
  end

  defp validate_first_sql!(sql) do
    normalized =
      normalize_sql(sql)

    if !String.contains?(
         normalized,
         "FROM unnest( $1::bigint[], $2::bigint[] ) AS pawn_structure_keys"
       ) do
      raise """
      production first-page compiler did not use the unnested
      pawn-structure key relation
      """
    end

    if !String.contains?(
         normalized,
         "JOIN positions AS p ON p.white_pawns = pawn_structure_keys.white_pawns AND p.black_pawns = pawn_structure_keys.black_pawns"
       ) do
      raise """
      production first-page compiler did not join the pawn key
      relation to positions through the production pawn index columns
      """
    end

    if String.contains?(
         normalized,
         "EXISTS"
       ) do
      raise """
      production first-page compiler unexpectedly used EXISTS
      """
    end

    if String.contains?(
         normalized,
         "UNION ALL"
       ) do
      raise """
      production first-page compiler unexpectedly expanded the
      edit neighborhood into UNION ALL branches
      """
    end

    if !String.contains?(
         normalized,
         "ORDER BY p.id LIMIT $3::bigint"
       ) do
      raise """
      production first-page compiler has an unexpected parameter
      or ordering layout
      """
    end

    :ok
  end

  defp validate_second_sql!(sql) do
    validate_first_relation_shape!(sql)

    normalized =
      normalize_sql(sql)

    if !String.contains?(
         normalized,
         "p.id > $4::bigint"
       ) do
      raise """
      production second-page compiler did not push the lower
      keyset bound into the position scan
      """
    end

    if !String.contains?(
         normalized,
         "p.id <= $3::bigint"
       ) do
      raise """
      production second-page compiler did not push the captured
      high-water bound into the position scan
      """
    end

    if !String.contains?(
         normalized,
         "ORDER BY p.id LIMIT $5::bigint"
       ) do
      raise """
      production second-page compiler has an unexpected parameter
      or ordering layout
      """
    end

    :ok
  end

  defp validate_first_relation_shape!(sql) do
    normalized =
      normalize_sql(sql)

    if !String.contains?(
         normalized,
         "FROM unnest( $1::bigint[], $2::bigint[] ) AS pawn_structure_keys"
       ) do
      raise """
      production compiler did not use the unnested pawn-structure
      key relation
      """
    end

    if !String.contains?(
         normalized,
         "JOIN positions AS p ON p.white_pawns = pawn_structure_keys.white_pawns AND p.black_pawns = pawn_structure_keys.black_pawns"
       ) do
      raise """
      production compiler did not join the key relation to positions
      """
    end

    if String.contains?(
         normalized,
         "EXISTS"
       ) do
      raise """
      production compiler unexpectedly used EXISTS
      """
    end

    if String.contains?(
         normalized,
         "UNION ALL"
       ) do
      raise """
      production compiler unexpectedly used UNION ALL
      """
    end

    :ok
  end

  defp position_store_page!(query, options) do
    case PositionStore.page(
           query,
           options
         ) do
      {
        :ok,
        %PositionStore.Page{} = page
      } ->
        page

      {:error, reason} ->
        raise """
        PositionStore paging failed:

        #{inspect(reason)}
        """
    end
  end

  defp query_rows(sql, parameters) do
    SQL.query!(
      Repo,
      sql,
      parameters
    ).rows
  end

  defp validate_compiled_rows!(
         rows,
         expected_maximum_position_id,
         expected_count,
         selectivity,
         after_position_id
       ) do
    if length(rows) !=
         expected_count do
      raise """
      expected #{expected_count} compiled-query rows,
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
          unexpected compiled-query row:

          #{inspect(row)}
          """
      end
    )

    position_ids =
      compiled_position_ids(rows)

    validate_position_ids!(
      position_ids,
      selectivity,
      after_position_id
    )

    rows
  end

  defp compiled_position_ids(rows) do
    Enum.map(
      rows,
      fn
        [
          _maximum_position_id,
          position_id
        ] ->
          position_id
      end
    )
  end

  defp validate_position_store_page!(
         %PositionStore.Page{entries: entries} = page,
         expected_count,
         selectivity,
         after_position_id
       ) do
    if length(entries) !=
         expected_count do
      raise """
      expected #{expected_count} PositionStore entries,
      got #{length(entries)}
      """
    end

    validate_position_ids!(
      entries,
      selectivity,
      after_position_id
    )

    page
  end

  defp validate_position_ids!(position_ids, selectivity, after_position_id) do
    if position_ids !=
         Enum.sort(position_ids) do
      raise """
      position IDs are not ordered
      """
    end

    if !Enum.all?(
         position_ids,
         fn position_id ->
           rem(
             position_id,
             selectivity
           ) == 0
         end
       ) do
      raise """
      result contains a position outside the edit-neighborhood fixture
      """
    end

    case {
      after_position_id,
      position_ids
    } do
      {
        nil,
        _position_ids
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
          first_position_id
          | _remaining
        ]
      }
      when first_position_id >
             after_position_id ->
        :ok

      {
        after_position_id,
        [
          first_position_id
          | _remaining
        ]
      } ->
        raise """
        expected second page to start after position #{after_position_id},
        got #{first_position_id}
        """
    end
  end

  defp encoded_distance_two_structures do
    distance_one =
      EditDistance.neighborhood(
        @source_structure,
        1
      )

    if length(distance_one) !=
         @expected_distance_one_neighbors + 1 do
      raise """
      benchmark source structure must produce
      #{@expected_distance_one_neighbors} distance-one neighbors,
      got #{length(distance_one) - 1}
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
      benchmark source structure must produce
      #{@expected_distance_two_keys} structures within distance <= 2,
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
    "PAWN_EDIT_PRODUCTION_BENCH_POSTINGS",
    "10000"
  )
  |> String.to_integer()

selectivity =
  System.get_env(
    "PAWN_EDIT_PRODUCTION_BENCH_SELECTIVITY",
    "100"
  )
  |> String.to_integer()

page_size =
  System.get_env(
    "PAWN_EDIT_PRODUCTION_BENCH_PAGE_SIZE",
    "100"
  )
  |> String.to_integer()

if posting_count <= 0 do
  raise """
  PAWN_EDIT_PRODUCTION_BENCH_POSTINGS must be positive
  """
end

if selectivity <= 0 do
  raise """
  PAWN_EDIT_PRODUCTION_BENCH_SELECTIVITY must be positive
  """
end

if page_size <= 0 do
  raise """
  PAWN_EDIT_PRODUCTION_BENCH_PAGE_SIZE must be positive
  """
end

if posting_count <
     page_size * 2 do
  raise """
  PAWN_EDIT_PRODUCTION_BENCH_POSTINGS must be at least twice
  PAWN_EDIT_PRODUCTION_BENCH_PAGE_SIZE so the benchmark has a
  full second page.
  """
end

try do
  IO.puts("""
  Building production PostgreSQL pawn edit-neighborhood fixture...

  neighborhood matches: #{posting_count}
  selectivity:          1/#{selectivity}
  rows:                 #{posting_count * selectivity}
  distance:             <= 2
  neighborhood keys:    4_022
  page size:            #{page_size}
  """)

  fixture =
    Benchmark.build(
      posting_count,
      selectivity
    )

  IO.puts("""
  Production pawn edit-neighborhood paging benchmark

  rows:                  #{fixture.row_count}
  positions table:       #{fixture.table_size} bytes
  pawn paging index:     #{fixture.pawn_index_size} bytes
  record unique index:   #{fixture.record_index_size} bytes
  total positions size:  #{fixture.total_size} bytes
  neighborhood keys:     #{fixture.structure_count}

  This benchmark uses the real positions table and production
  positions_pawn_structure_index.

  It separates:

    * execution of already compiled production SQL
    * complete PositionStore.page/2 execution
    * distance-2 query construction
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
