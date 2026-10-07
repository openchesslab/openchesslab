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

  test "compiles a top-level edit neighborhood as an unnested game-search key relation" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_edit_neighborhood(2)

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

    assert String.contains?(
             sql,
             "FROM unnest( $1::bigint[], $2::bigint[] ) AS pawn_structure_keys"
           )

    assert String.contains?(
             sql,
             "JOIN positions AS p ON p.white_pawns = pawn_structure_keys.white_pawns AND p.black_pawns = pawn_structure_keys.black_pawns"
           )

    assert String.contains?(
             sql,
             "JOIN game_occurrences AS go ON go.position_id = p.id"
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
             "ORDER BY p.id, go.id, gr.id LIMIT $3::bigint"
           )

    assert [
             white_pawns,
             black_pawns,
             101
           ] =
             parameters

    assert is_list(white_pawns)
    assert is_list(black_pawns)
  end

  test "keeps the cursor position in the edit-neighborhood relation on the next page" do
    query =
      asymmetric_position()
      |> Query.pawn_structure_edit_neighborhood(2)

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

    assert String.contains?(
             sql,
             "SELECT $3::bigint, $4::bigint, $5::bigint, p.id"
           )

    assert String.contains?(
             sql,
             "p.id >= $6::bigint"
           )

    assert String.contains?(
             sql,
             "p.id <= $3::bigint"
           )

    assert String.contains?(
             sql,
             "go.id <= $4::bigint"
           )

    assert String.contains?(
             sql,
             "gr.id <= $5::bigint"
           )

    assert String.contains?(
             sql,
             "( go.position_id, go.id ) >= ( $6::bigint, $7::bigint )"
           )

    assert String.contains?(
             sql,
             "( go.position_id, go.id, gr.id ) > ( $6::bigint, $7::bigint, $8::bigint )"
           )

    assert String.contains?(
             sql,
             "ORDER BY p.id, go.id, gr.id LIMIT $9::bigint"
           )

    assert [
             white_pawns,
             black_pawns,
             40,
             50,
             60,
             10,
             20,
             30,
             101
           ] =
             parameters

    assert is_list(white_pawns)
    assert is_list(black_pawns)
  end

  test "pushes position and record residuals into the edit-neighborhood relation" do
    position =
      asymmetric_position()

    position_query =
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
             "gr.metadata @> $4::jsonb"
           )

    assert String.contains?(
             sql,
             "ORDER BY p.id, go.id, gr.id LIMIT $5::bigint"
           )

    assert length(parameters) ==
             5

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
             PostgresQuery.compile_first(
               query,
               GameRecordQuery.match_all(),
               101
             )

    sql =
      normalize_sql(sql)

    assert String.contains?(
             sql,
             "FROM positions AS p JOIN game_occurrences AS go"
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

    assert String.contains?(
             sql,
             "ORDER BY p.id, go.id, gr.id LIMIT $4::bigint"
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
