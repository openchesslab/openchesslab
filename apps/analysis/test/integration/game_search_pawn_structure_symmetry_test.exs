defmodule Analysis.GameSearchPawnStructureSymmetryTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordStore
  alias Analysis.GameSearch
  alias Analysis.GameStore
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "continues within the cursor position and preserves all high-water marks" do
    source =
      position(
        "b4",
        "f6"
      )

    reflected =
      position(
        "g4",
        "c6"
      )

    {
      source_position_id,
      source_game_id
    } =
      stored_game(source)

    {
      reflected_position_id,
      reflected_game_id
    } =
      stored_game(reflected)

    source_records =
      Enum.map(
        1..3,
        fn index ->
          record =
            GameRecord.new(
              "source-#{index}",
              source_game_id
            )

          assert :ok =
                   GameRecordStore.insert(record)

          record
        end
      )

    reflected_record =
      GameRecord.new(
        "reflected",
        reflected_game_id
      )

    assert :ok =
             GameRecordStore.insert(reflected_record)

    query =
      Query.pawn_structure_symmetries(source)

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: cursor
             }
           } =
             GameSearch.page(
               query,
               limit: 2
             )

    assert %GameSearch.Cursor{} =
             cursor

    assert Enum.map(
             first_page,
             fn
               {
                 record,
                 occurrence
               } ->
                 {
                   record,
                   occurrence.position_id
                 }
             end
           ) ==
             [
               {
                 Enum.at(
                   source_records,
                   0
                 ),
                 source_position_id
               },
               {
                 Enum.at(
                   source_records,
                   1
                 ),
                 source_position_id
               }
             ]

    late_source_record =
      GameRecord.new(
        "late-source",
        source_game_id
      )

    assert :ok =
             GameRecordStore.insert(late_source_record)

    late_position =
      source
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    {
      late_position_id,
      late_game_id
    } =
      stored_game(late_position)

    assert late_position_id >
             reflected_position_id

    late_position_record =
      GameRecord.new(
        "late-position",
        late_game_id
      )

    assert :ok =
             GameRecordStore.insert(late_position_record)

    assert {
             :ok,
             %GameSearch.Page{
               entries: second_page,
               next: nil
             }
           } =
             GameSearch.page(
               query,
               limit: 2,
               cursor: cursor
             )

    assert Enum.map(
             second_page,
             fn
               {
                 record,
                 occurrence
               } ->
                 {
                   record,
                   occurrence.position_id
                 }
             end
           ) ==
             [
               {
                 Enum.at(
                   source_records,
                   2
                 ),
                 source_position_id
               },
               {
                 reflected_record,
                 reflected_position_id
               }
             ]

    returned_records =
      first_page
      |> Kernel.++(second_page)
      |> Enum.map(fn
        {
          record,
          _occurrence
        } ->
          record
      end)

    refute late_source_record in returned_records
    refute late_position_record in returned_records
  end

  test "combines symmetry, residual position and record predicates" do
    source =
      position(
        "b4",
        "f6"
      )

    reflected =
      position(
        "g4",
        "c6"
      )

    reflected_with_rook =
      reflected
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    {
      source_position_id,
      source_game_id
    } =
      stored_game(source)

    {
      _reflected_position_id,
      reflected_game_id
    } =
      stored_game(reflected)

    {
      _reflected_with_rook_position_id,
      reflected_with_rook_game_id
    } =
      stored_game(reflected_with_rook)

    matching_record =
      GameRecord.new(
        "matching",
        source_game_id,
        %{
          "white" => "Magnus Carlsen"
        }
      )

    excluded_by_record_query =
      GameRecord.new(
        "excluded-record",
        reflected_game_id,
        %{
          "white" => "Other Player"
        }
      )

    excluded_by_position_query =
      GameRecord.new(
        "excluded-position",
        reflected_with_rook_game_id,
        %{
          "white" => "Magnus Carlsen"
        }
      )

    for record <- [
          matching_record,
          excluded_by_record_query,
          excluded_by_position_query
        ] do
      assert :ok =
               GameRecordStore.insert(record)
    end

    position_query =
      Query.all([
        Query.pawn_structure_symmetries(source),
        Query.property(
          :material,
          PositionProperties.material(source)
        )
      ])

    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^matching_record,
                   occurrence
                 }
               ],
               next: nil
             }
           } =
             GameSearch.page(
               position_query,
               record_query,
               limit: 10
             )

    assert occurrence.position_id ==
             source_position_id
  end

  defp stored_game(position) do
    position_id =
      PositionStore.append(position)

    assert is_integer(position_id)

    assert position_id >
             0

    content =
      GameContent.new(position_id)

    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [
                 position_id
               ]
             )

    {
      position_id,
      game_id
    }
  end

  defp position(white_square, black_square) do
    Position.new()
    |> Position.put_piece(
      Square.from_algebraic(white_square),
      {:white, :pawn}
    )
    |> Position.put_piece(
      Square.from_algebraic(black_square),
      {:black, :pawn}
    )
  end
end
