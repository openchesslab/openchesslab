defmodule Analysis.GameSearchTest do
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
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

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

  test "executes position and record predicates in one PostgreSQL query" do
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

    {
      first_position_id,
      first_game_id
    } =
      stored_game(first_position)

    {
      _second_position_id,
      second_game_id
    } =
      stored_game(second_position)

    matching_record =
      GameRecord.new(
        "record-1",
        first_game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "Wijk aan Zee"
        }
      )

    excluded_by_record_query =
      GameRecord.new(
        "record-2",
        first_game_id,
        %{
          "white" => "Other Player",
          "event" => "Wijk aan Zee"
        }
      )

    excluded_by_position_query =
      GameRecord.new(
        "record-3",
        second_game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "London"
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

    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    {
      result,
      query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.equivalent(first_position),
          record_query,
          limit: 10
        )
      end)

    assert query_count ==
             1

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
             result

    assert occurrence.game_id ==
             first_game_id

    assert occurrence.ply ==
             0

    assert occurrence.position_id ==
             first_position_id
  end

  test "pages the joined result relation without duplicates or omissions" do
    {
      position_id,
      game_id
    } =
      stored_game(Position.starting_position())

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

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: first_cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
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
               Query.match_all(),
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
               Query.match_all(),
               limit: 2,
               cursor: second_cursor
             )

    matches =
      first_page ++
        second_page ++
        third_page

    assert Enum.map(
             matches,
             fn {record, occurrence} ->
               {
                 record,
                 occurrence.game_id,
                 occurrence.ply,
                 occurrence.position_id
               }
             end
           ) ==
             Enum.map(
               records,
               fn record ->
                 {
                   record,
                   game_id,
                   0,
                   position_id
                 }
               end
             )
  end

  test "limit applies to actual search results rather than candidate positions" do
    records =
      Enum.map(
        1..5,
        fn index ->
          position =
            if index == 1 do
              Position.starting_position()
            else
              position_after_pawn_move(index)
            end

          {
            _position_id,
            game_id
          } =
            stored_game(position)

          excluded =
            GameRecord.new(
              "excluded-#{index}",
              game_id,
              %{
                "white" => "Other Player"
              }
            )

          matching =
            GameRecord.new(
              "matching-#{index}",
              game_id,
              %{
                "white" => "Magnus Carlsen"
              }
            )

          assert :ok =
                   GameRecordStore.insert(excluded)

          assert :ok =
                   GameRecordStore.insert(matching)

          matching
        end
      )

    query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               query,
               limit: 3
             )

    assert length(first_page) ==
             3

    assert %GameSearch.Cursor{} =
             cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: second_page,
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               query,
               limit: 3,
               cursor: cursor
             )

    assert Enum.map(
             first_page ++ second_page,
             fn {record, _occurrence} ->
               record
             end
           ) ==
             records
  end

  test "excludes rows inserted after the first page snapshot" do
    first_position =
      Position.starting_position()

    {
      first_position_id,
      first_game_id
    } =
      stored_game(first_position)

    first =
      GameRecord.new(
        "record-1",
        first_game_id
      )

    second =
      GameRecord.new(
        "record-2",
        first_game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^first,
                   first_occurrence
                 }
               ],
               next: cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 1
             )

    assert first_occurrence.position_id ==
             first_position_id

    later_record =
      GameRecord.new(
        "record-3",
        first_game_id
      )

    assert :ok =
             GameRecordStore.insert(later_record)

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    {
      _second_position_id,
      second_game_id
    } =
      stored_game(second_position)

    later_game_record =
      GameRecord.new(
        "record-4",
        second_game_id
      )

    assert :ok =
             GameRecordStore.insert(later_game_record)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^second,
                   second_occurrence
                 }
               ],
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 10,
               cursor: cursor
             )

    assert second_occurrence.position_id ==
             first_position_id
  end

  test "skips matching positions without concrete game results" do
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

    {
      second_position_id,
      game_id
    } =
      stored_game(second_position)

    record =
      GameRecord.new(
        "record-1",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^record,
                   occurrence
                 }
               ],
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 10
             )

    assert occurrence.position_id ==
             second_position_id

    refute occurrence.position_id ==
             first_position_id
  end

  test "match-none queries return an empty page without querying PostgreSQL" do
    {
      position_result,
      position_query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.match_none(),
          limit: 10
        )
      end)

    assert position_result ==
             {
               :ok,
               %GameSearch.Page{
                 entries: [],
                 next: nil
               }
             }

    assert position_query_count ==
             0

    {
      record_result,
      record_query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.match_all(),
          GameRecordQuery.match_none(),
          limit: 10
        )
      end)

    assert record_result ==
             {
               :ok,
               %GameSearch.Page{
                 entries: [],
                 next: nil
               }
             }

    assert record_query_count ==
             0
  end

  test "requires a positive bounded page limit" do
    assert GameSearch.page(
             Query.match_all(),
             []
           ) ==
             {:error, :missing_limit}

    assert GameSearch.page(
             Query.match_all(),
             limit: 0
           ) ==
             {:error, :invalid_limit}

    assert GameSearch.page(
             Query.match_all(),
             limit: -1
           ) ==
             {:error, :invalid_limit}
  end

  test "rejects invalid cursor values" do
    assert GameSearch.page(
             Query.match_all(),
             limit: 10,
             cursor: make_ref()
           ) ==
             {:error, :invalid_cursor}
  end

  def handle_query(_event, _measurements, _metadata, parent) do
    send(
      parent,
      :game_search_query
    )

    :ok
  end

  defp stored_game(position) do
    position_id =
      PositionStore.append(position)

    assert is_integer(position_id)
    assert position_id > 0

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

  defp query_count(fun) when is_function(fun, 0) do
    event =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)
      |> Kernel.++([:query])

    handler_id = {
      __MODULE__,
      make_ref()
    }

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_query/4,
        self()
      )

    try do
      result =
        fun.()

      {
        result,
        drain_query_count(0)
      }
    after
      :telemetry.detach(handler_id)

      drain_query_count(0)
    end
  end

  defp drain_query_count(count) do
    receive do
      :game_search_query ->
        drain_query_count(count + 1)
    after
      0 ->
        count
    end
  end

  defp position_after_pawn_move(index) do
    file =
      Enum.at(
        [
          "a",
          "b",
          "c",
          "d",
          "e",
          "f",
          "g",
          "h"
        ],
        index - 2
      )

    {:ok, position} =
      Position.apply_move(
        Position.starting_position(),
        move(
          "#{file}2",
          "#{file}3"
        )
      )

    position
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
