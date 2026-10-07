defmodule Analysis.PositionQueryPostgresPageTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionQuery.PostgresPage
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "compiles first symmetry page as ordered UNION ALL equality scans" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_symmetries()

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresPage.compile_first(
               query,
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
             "ORDER BY matches.id LIMIT $9::bigint"
           )

    assert length(parameters) ==
             9

    assert List.last(parameters) ==
             101
  end

  test "pushes keyset bounds into every symmetry branch" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_symmetries()

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresPage.compile_next(
               query,
               40,
               10,
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
             "p.id > $10::bigint"
           ) ==
             4

    assert occurrences(
             sql,
             "p.id <= $9::bigint"
           ) ==
             4

    assert String.contains?(
             sql,
             "SELECT $9::bigint AS maximum_position_id, matches.id"
           )

    assert String.contains?(
             sql,
             "ORDER BY matches.id LIMIT $11::bigint"
           )

    assert Enum.take(
             parameters,
             -3
           ) ==
             [
               40,
               10,
               101
             ]
  end

  test "pushes a top-level AND residual predicate into every symmetry branch" do
    position =
      asymmetric_position()

    query =
      Query.all([
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
             PostgresPage.compile_first(
               query,
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

    assert String.contains?(
             sql,
             "ORDER BY matches.id LIMIT $10::bigint"
           )

    assert length(parameters) ==
             10

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
             PostgresPage.compile_first(
               query,
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
             "FROM positions AS p WHERE"
           )

    assert length(parameters) ==
             10

    assert List.last(parameters) ==
             101
  end

  test "uses one ordered equality scan when symmetries collapse to one structure" do
    query =
      Position.starting_position()
      |> Query.pawn_structure_symmetries()

    assert {
             :ok,
             sql,
             parameters
           } =
             PostgresPage.compile_first(
               query,
               101
             )

    sql =
      normalize_sql(sql)

    refute String.contains?(
             sql,
             "UNION ALL"
           )

    assert occurrences(
             sql,
             "ORDER BY p.id"
           ) ==
             1

    assert String.contains?(
             sql,
             "ORDER BY matches.id LIMIT $3::bigint"
           )

    assert length(parameters) ==
             3

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
