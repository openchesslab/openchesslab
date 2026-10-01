defmodule Analysis.GameSearchTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameRecordStore.Memory
  alias Analysis.GameSearch
  alias Analysis.GameStore
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  setup do
    previous_game_store =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    previous_game_record_store =
      Application.get_env(
        :analysis,
        GameRecordStore,
        :not_configured
      )

    unique =
      System.unique_integer([
        :positive,
        :monotonic
      ])

    game_server =
      :"game-search-game-store-#{unique}"

    record_server =
      :"game-search-record-store-#{unique}"

    start_supervised!({
      GameStore,
      server: game_server
    })

    start_supervised!({
      Memory,
      name: record_server
    })

    Application.put_env(
      :analysis,
      GameStore,
      server: game_server
    )

    Application.put_env(
      :analysis,
      GameRecordStore,
      adapter: Memory,
      store: record_server
    )

    Repo.query!(
      """
      TRUNCATE TABLE
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    on_exit(fn ->
      restore_config(
        GameStore,
        previous_game_store
      )

      restore_config(
        GameRecordStore,
        previous_game_record_store
      )
    end)

    :ok
  end

  test "returns an empty page when the position query has no matches" do
    assert GameSearch.query_page(
             Query.match_none(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "pages concrete game occurrences across matching positions without duplicates or omissions" do
    first_position =
      Position.starting_position()

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    first_position_id =
      PositionStore.append(first_position)

    second_position_id =
      PositionStore.append(second_position)

    assert {:ok, first_game_id} =
             GameStore.put(
               <<"game-1">>,
               GameContent.new(first_position_id),
               [
                 first_position_id
               ]
             )

    assert {:ok, second_game_id} =
             GameStore.put(
               <<"game-2">>,
               GameContent.new(second_position_id),
               [
                 second_position_id
               ]
             )

    first_record =
      GameRecord.new(
        "record-1",
        first_game_id
      )

    second_record =
      GameRecord.new(
        "record-2",
        first_game_id
      )

    third_record =
      GameRecord.new(
        "record-3",
        second_game_id
      )

    assert :ok =
             GameRecordStore.insert(first_record)

    assert :ok =
             GameRecordStore.insert(second_record)

    assert :ok =
             GameRecordStore.insert(third_record)

    assert {
             :ok,
             first_page,
             cursor
           } =
             GameSearch.query_page(
               Query.match_all(),
               2
             )

    assert length(first_page) ==
             2

    assert {
             :ok,
             second_page,
             :done
           } =
             GameSearch.next_query_page(
               cursor,
               2
             )

    assert length(second_page) ==
             1

    matches =
      first_page ++
        second_page

    assert MapSet.new(
             Enum.map(
               matches,
               fn {record, occurrence} ->
                 {
                   record,
                   occurrence.game_id,
                   occurrence.ply,
                   occurrence.position_id
                 }
               end
             )
           ) ==
             MapSet.new([
               {
                 first_record,
                 first_game_id,
                 0,
                 first_position_id
               },
               {
                 second_record,
                 first_game_id,
                 0,
                 first_position_id
               },
               {
                 third_record,
                 second_game_id,
                 0,
                 second_position_id
               }
             ])
  end

  test "does not create a cursor when the complete search fits in the first page" do
    position_id =
      PositionStore.append(Position.starting_position())

    assert {:ok, game_id} =
             GameStore.put(
               <<"game">>,
               GameContent.new(position_id),
               [
                 position_id
               ]
             )

    record =
      GameRecord.new(
        "record-1",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert {
             :ok,
             [
               {
                 ^record,
                 occurrence
               }
             ],
             :done
           } =
             GameSearch.query_page(
               Query.match_all(),
               1
             )

    assert occurrence.game_id ==
             game_id

    assert occurrence.ply ==
             0

    assert occurrence.position_id ==
             position_id
  end

  test "skips matching positions without concrete games" do
    first_position =
      Position.starting_position()

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    first_position_id =
      PositionStore.append(first_position)

    second_position_id =
      PositionStore.append(second_position)

    assert {:ok, game_id} =
             GameStore.put(
               <<"game">>,
               GameContent.new(second_position_id),
               [
                 second_position_id
               ]
             )

    record =
      GameRecord.new(
        "record-1",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert {
             :ok,
             matches,
             :done
           } =
             GameSearch.query_page(
               Query.match_all(),
               10
             )

    assert [
             {
               ^record,
               occurrence
             }
           ] =
             matches

    assert occurrence.position_id ==
             second_position_id

    refute occurrence.position_id ==
             first_position_id
  end

  test "closes an unfinished search cursor" do
    position_id =
      PositionStore.append(Position.starting_position())

    assert {:ok, game_id} =
             GameStore.put(
               <<"game">>,
               GameContent.new(position_id),
               [
                 position_id
               ]
             )

    first =
      GameRecord.new(
        "record-1",
        game_id
      )

    second =
      GameRecord.new(
        "record-2",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert {
             :ok,
             [_match],
             cursor
           } =
             GameSearch.query_page(
               Query.match_all(),
               1
             )

    assert :ok =
             GameSearch.close_query(cursor)

    assert GameSearch.next_query_page(
             cursor,
             1
           ) ==
             {
               :error,
               {
                 :game_records,
                 {
                   :game_record_store,
                   :cursor_not_found
                 }
               }
             }
  end

  defp restore_config(module, :not_configured) do
    Application.delete_env(
      :analysis,
      module
    )
  end

  defp restore_config(module, value) do
    Application.put_env(
      :analysis,
      module,
      value
    )
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
