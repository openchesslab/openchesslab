alias OpenChessLab.Database.PawnStructureEditNeighborhoodSemiJoinPlanPostgresBenchmark,
  as: Benchmark

Logger.configure(level: :warning)

defmodule OpenChessLab.Database.PawnStructureEditNeighborhoodSemiJoinPlanPostgresBenchmark do
  @moduledoc false

  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.PawnStructure
  alias Ecto.Adapters.SQL
  alias OpenChessLab.Repo

  @source_structure %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_keys 4_022
  @page_size 100

  def run do
    query =
      PositionQuery.pawn_structure_edit_neighborhood(
        @source_structure,
        2
      )

    requested_rows = @page_size + 1

    {:ok, pair_first_sql, pair_first_params} =
      PostgresPage.compile_first(
        query,
        requested_rows
      )

    [white_keys, black_keys, ^requested_rows] =
      pair_first_params

    if length(white_keys) != @expected_keys or
         length(black_keys) != @expected_keys do
      raise "expected #{@expected_keys} neighborhood keys"
    end

    encoded_keys = Enum.zip(white_keys, black_keys)

    if length(Enum.uniq(encoded_keys)) != @expected_keys do
      raise "benchmark requires distinct neighborhood keys"
    end

    [[row_count]] =
      SQL.query!(
        Repo,
        "SELECT count(*) FROM positions",
        []
      ).rows

    if row_count != 1_000_000 do
      raise """
      Expected the existing 1,000,000-row benchmark fixture.

      Found #{row_count} rows.

      This diagnostic intentionally does not rebuild fixtures.
      """
    end

    first_rows =
      query_rows(
        pair_first_sql,
        pair_first_params
      )

    if length(first_rows) != requested_rows do
      raise "existing fixture does not provide a full first page"
    end

    [[maximum_position_id, _first_id] | _remaining] =
      first_rows

    [_maximum, last_position_id] =
      Enum.at(first_rows, @page_size - 1)

    {:ok, pair_second_sql, pair_second_params} =
      PostgresPage.compile_next(
        query,
        maximum_position_id,
        last_position_id,
        requested_rows
      )

    expected_second_params = [
      white_keys,
      black_keys,
      maximum_position_id,
      last_position_id,
      requested_rows
    ]

    if pair_second_params != expected_second_params do
      raise "unexpected production second-page parameters"
    end

    IO.puts("""
    PostgreSQL pawn-neighborhood semi-join plan diagnostic

    Existing positions:  #{row_count}
    Neighborhood keys:   #{@expected_keys}
    Page size:           #{@page_size}
    Requested rows:      #{requested_rows}
    Maximum position ID: #{maximum_position_id}
    Second-page cursor:  #{last_position_id}

    No fixture creation, schema changes or timed benchmark loops.
    """)

    show_plan(
      "Production pair relation: first page",
      pair_first_sql,
      pair_first_params
    )

    show_plan(
      "EXISTS semi-join: first page",
      semijoin_first_sql(),
      pair_first_params
    )

    show_plan(
      "Production pair relation: second page",
      pair_second_sql,
      pair_second_params
    )

    show_plan(
      "EXISTS semi-join: second page",
      semijoin_second_sql(),
      pair_second_params
    )
  end

  defp semijoin_first_sql do
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
    WHERE EXISTS (
      SELECT 1
      FROM unnest(
        $1::bigint[],
        $2::bigint[]
      ) AS pawn_structure_keys(
        white_pawns,
        black_pawns
      )
      WHERE
        pawn_structure_keys.white_pawns = p.white_pawns
        AND pawn_structure_keys.black_pawns = p.black_pawns
    )
    ORDER BY p.id
    LIMIT $3::bigint
    """
  end

  defp semijoin_second_sql do
    """
    SELECT
      $3::bigint AS maximum_position_id,
      p.id
    FROM positions AS p
    WHERE
      p.id > $4::bigint
      AND p.id <= $3::bigint
      AND EXISTS (
        SELECT 1
        FROM unnest(
          $1::bigint[],
          $2::bigint[]
        ) AS pawn_structure_keys(
          white_pawns,
          black_pawns
        )
        WHERE
          pawn_structure_keys.white_pawns = p.white_pawns
          AND pawn_structure_keys.black_pawns = p.black_pawns
      )
    ORDER BY p.id
    LIMIT $5::bigint
    """
  end

  defp query_rows(sql, parameters) do
    SQL.query!(
      Repo,
      sql,
      parameters
    ).rows
  end

  defp show_plan(label, sql, parameters) do
    plan =
      Repo
      |> SQL.query!(
        """
        EXPLAIN (
          ANALYZE FALSE,
          COSTS TRUE,
          VERBOSE FALSE
        )
        #{sql}
        """,
        parameters
      )
      |> Map.fetch!(:rows)
      |> Enum.map_join("\n", fn [line] -> line end)

    IO.puts("""

    ============================================================
    #{label}
    ============================================================

    #{plan}
    """)
  end
end

database_url =
  System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL is required"

if URI.parse(database_url).path != "/openchesslab_bench" do
  raise "This diagnostic must use openchesslab_bench"
end

Benchmark.run()
