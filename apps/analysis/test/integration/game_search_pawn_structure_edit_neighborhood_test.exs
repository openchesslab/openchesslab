defmodule Analysis.GameSearchPawnStructureEditNeighborhoodTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameSearch
  alias Analysis.GameStore
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position
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

  test "pages every record belonging to one matching edit-neighborhood position" do
    source =
      position([
        {"d4", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    {
      position_id,
      game_id
    } =
      stored_game(source)

    records =
      Enum.map(
        1..5,
        fn index ->
          record =
            GameRecord.new(
              "record-#{index}",
              game_id,
              %{
                "index" => index
              }
            )

          assert :ok =
                   GameRecordStore.insert(record)

          record
        end
      )

    query =
      Query.pawn_structure_edit_neighborhood(
        source,
        2
      )

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: first_cursor
             }
           } =
             GameSearch.page(
               query,
               limit: 2
             )

    assert %GameSearch.Cursor{} =
             first_cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: second_page,
               next: second_cursor
             }
           } =
             GameSearch.page(
               query,
               limit: 2,
               cursor: first_cursor
             )

    assert %GameSearch.Cursor{} =
             second_cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: third_page,
               next: nil
             }
           } =
             GameSearch.page(
               query,
               limit: 2,
               cursor: second_cursor
             )

    entries =
      first_page ++
        second_page ++
        third_page

    assert Enum.map(
             entries,
             fn
               {
                 record,
                 occurrence
               } ->
                 {
                   record,
                   occurrence.position_id,
                   occurrence.game_id,
                   occurrence.ply
                 }
             end
           ) ==
             Enum.map(
               records,
               fn record ->
                 {
                   record,
                   position_id,
                   game_id,
                   0
                 }
               end
             )
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

    assert {
             :ok,
             game_id
           } =
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

  defp position(pieces) do
    Enum.reduce(
      pieces,
      Position.new(),
      fn
        {
          square,
          piece
        },
        position ->
          Position.put_piece(
            position,
            Square.from_algebraic(square),
            piece
          )
      end
    )
  end
end
