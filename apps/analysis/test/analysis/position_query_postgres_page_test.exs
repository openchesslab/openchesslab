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

  test "compiles a top-level edit neighborhood as an unnested key relation" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_edit_neighborhood(2)

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

    assert String.contains?(
             sql,
             "FROM unnest( $1::bigint[], $2::bigint[] ) AS pawn_structure_keys"
           )

    assert String.contains?(
             sql,
             "JOIN positions AS p ON p.white_pawns = pawn_structure_keys.white_pawns AND p.black_pawns = pawn_structure_keys.black_pawns"
           )

    refute String.contains?(
             sql,
             "EXISTS"
           )

    refute String.contains?(
             sql,
             "UNION ALL"
           )

    assert String.contains?(
             sql,
             "ORDER BY p.id LIMIT $3::bigint"
           )

    assert [
             white_pawns,
             black_pawns,
             101
           ] =
             parameters

    assert is_list(white_pawns)
    assert is_list(black_pawns)

    assert length(white_pawns) ==
             length(black_pawns)

    assert length(white_pawns) >
             1
  end

  test "pushes position keyset bounds into the edit-neighborhood relation route" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_edit_neighborhood(2)

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

    assert String.contains?(
             sql,
             "SELECT $3::bigint AS maximum_position_id, p.id"
           )

    assert String.contains?(
             sql,
             "p.id > $4::bigint"
           )

    assert String.contains?(
             sql,
             "p.id <= $3::bigint"
           )

    assert String.contains?(
             sql,
             "ORDER BY p.id LIMIT $5::bigint"
           )

    assert [
             white_pawns,
             black_pawns,
             40,
             10,
             101
           ] =
             parameters

    assert is_list(white_pawns)
    assert is_list(black_pawns)
  end

  test "pushes a top-level AND residual into the edit-neighborhood relation route" do
    position =
      asymmetric_position()

    query =
      Query.all([
        Query.pawn_structure_edit_neighborhood(
          position,
          2
        ),
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

    assert String.contains?(
             sql,
             "FROM unnest( $1::bigint[], $2::bigint[] ) AS pawn_structure_keys"
           )

    assert occurrences(
             sql,
             "FROM position_features AS f"
           ) ==
             1

    assert String.contains?(
             sql,
             "ORDER BY p.id LIMIT $4::bigint"
           )

    assert length(parameters) ==
             4

    assert List.last(parameters) ==
             101
  end

  test "keeps an edit neighborhood inside a generic OR on the EXISTS fallback" do
    position =
      asymmetric_position()

    query =
      Query.any([
        Query.pawn_structure_edit_neighborhood(
          position,
          2
        ),
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

    assert String.contains?(
             sql,
             "FROM positions AS p WHERE"
           )

    assert String.contains?(
             sql,
             "EXISTS ( SELECT 1 FROM unnest( $1::bigint[], $2::bigint[] )"
           )

    refute String.contains?(
             sql,
             "JOIN positions AS p ON p.white_pawns = pawn_structure_keys.white_pawns"
           )

    assert String.contains?(
             sql,
             " OR "
           )

    assert length(parameters) ==
             4

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
