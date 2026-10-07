defmodule Analysis.GameSearchPostgresQueryTest do
  use ExUnit.Case, async: true

  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch.PostgresQuery
  alias Analysis.PositionQuery, as: Query
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "compiles first pawn symmetry game-search page as ordered UNION ALL scans" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_symmetries()

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresQuery.compile_first(
               query,
               GameRecordQuery.match_all(),
               101
             )

    sql =
      normalize_sql(sql)

    assert occurrences(
             sql,
             "UNION ALL"
           ) ==
             3

    assert occurrences(
             sql,
             "ORDER BY p.id"
           ) ==
             4

    refute String.contains?(
             sql,
             " OR "
           )

    assert String.contains?(
             sql,
             ") AS matches JOIN game_occurrences AS go ON go.position_id = matches.id"
           )

    assert String.contains?(
             sql,
             "ORDER BY matches.id, go.id, gr.id LIMIT $9::bigint"
           )

    assert length(parameters) ==
             9

    assert List.last(parameters) ==
             101
  end

  test "keeps the cursor position in every symmetry branch on the next page" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_symmetries()

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresQuery.compile_next(
               query,
               GameRecordQuery.match_all(),
               40,
               50,
               60,
               10,
               20,
               30,
               101
             )

    sql =
      normalize_sql(sql)

    assert occurrences(
             sql,
             "UNION ALL"
           ) ==
             3

    assert occurrences(
             sql,
             "p.id >= $12::bigint"
           ) ==
             4

    assert occurrences(
             sql,
             "p.id <= $9::bigint"
           ) ==
             4

    assert String.contains?(
             sql,
             "SELECT $9::bigint, $10::bigint, $11::bigint, matches.id"
           )

    assert String.contains?(
             sql,
             "( go.position_id, go.id ) >= ( $12::bigint, $13::bigint )"
           )

    assert String.contains?(
             sql,
             "( go.position_id, go.id, gr.id ) > ( $12::bigint, $13::bigint, $14::bigint )"
           )

    assert String.contains?(
             sql,
             "ORDER BY matches.id, go.id, gr.id LIMIT $15::bigint"
           )

    assert Enum.take(
             parameters,
             -7
           ) ==
             [
               40,
               50,
               60,
               10,
               20,
               30,
               101
             ]
  end

  test "pushes a top-level position residual into every symmetry branch" do
    position =
      asymmetric_position()

    position_query =
      Query.all([
        Query.pawn_structure_symmetries(position),
        Query.property(
          :material,
          PositionProperties.material(position)
        )
      ])

    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresQuery.compile_first(
               position_query,
               record_query,
               101
             )

    sql =
      normalize_sql(sql)

    assert occurrences(
             sql,
             "UNION ALL"
           ) ==
             3

    assert occurrences(
             sql,
             "FROM position_features AS f"
           ) ==
             4

    assert occurrences(
             sql,
             "gr.metadata @> $10::jsonb"
           ) ==
             1

    assert String.contains?(
             sql,
             "ORDER BY matches.id, go.id, gr.id LIMIT $11::bigint"
           )

    assert length(parameters) ==
             11

    assert List.last(parameters) ==
             101
  end

  test "does not rewrite a generic OR containing a symmetry query" do
    position =
      asymmetric_position()

    query =
      Query.any([
        Query.pawn_structure_symmetries(position),
        Query.property(
          :material,
          PositionProperties.material(position)
        )
      ])

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresQuery.compile_first(
               query,
               GameRecordQuery.match_all(),
               101
             )

    sql =
      normalize_sql(sql)

    refute String.contains?(
             sql,
             "UNION ALL"
           )

    assert String.contains?(
             sql,
             " OR "
           )

    assert String.contains?(
             sql,
             "FROM positions AS p JOIN game_occurrences AS go"
           )

    assert String.contains?(
             sql,
             "ORDER BY p.id, go.id, gr.id LIMIT $10::bigint"
           )

    assert length(parameters) ==
             10

    assert List.last(parameters) ==
             101
  end

  defp asymmetric_position do
    Position.new()
    |> Position.put_piece(
      Square.from_algebraic("b4"),
      {:white, :pawn}
    )
    |> Position.put_piece(
      Square.from_algebraic("f6"),
      {:black, :pawn}
    )
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
end
