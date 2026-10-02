defmodule Analysis.PostgresGameSearchRepositoryTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordRepository.Postgres, as: GameRecordRepository
  alias Analysis.GameRepository.Postgres, as: GameRepository
  alias Analysis.GameSearchRepository.Postgres, as: GameSearchRepository
  alias Analysis.PositionQuery
  alias Analysis.PositionRepository.Postgres, as: PositionRepository
  alias Chess.Move
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

  test "executes position and game-record predicates in one PostgreSQL query" do
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
               GameRecordRepository.insert(record)
    end

    position_query =
      PositionQuery.equivalent(first_position)

    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    {
      result,
      query_count
    } =
      query_count(fn ->
        GameSearchRepository.query_page(
          position_query,
          record_query,
          10
        )
      end)

    assert query_count ==
             1

    assert {
             :ok,
             [
               {
                 ^matching_record,
                 occurrence
               }
             ],
             :done
           } =
             result

    assert occurrence.game_id ==
             first_game_id

    assert occurrence.ply ==
             0

    assert occurrence.position_id ==
             first_position_id
  end

  test "pages the joined result with a compound keyset without duplicates or omissions" do
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
                   GameRecordRepository.insert(record)

          record
        end
      )

    assert {
             :ok,
             first_page,
             cursor
           } =
             GameSearchRepository.query_page(
               PositionQuery.match_all(),
               GameRecordQuery.match_all(),
               2
             )

    assert %GameSearchRepository.Cursor{} =
             cursor

    assert {
             :ok,
             second_page,
             cursor
           } =
             GameSearchRepository.next_query_page(
               cursor,
               2
             )

    assert %GameSearchRepository.Cursor{} =
             cursor

    assert {
             :ok,
             third_page,
             :done
           } =
             GameSearchRepository.next_query_page(
               cursor,
               2
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

  test "excludes rows inserted after the search snapshot" do
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
             GameRecordRepository.insert(first)

    assert :ok =
             GameRecordRepository.insert(second)

    assert {
             :ok,
             [
               {
                 ^first,
                 first_occurrence
               }
             ],
             cursor
           } =
             GameSearchRepository.query_page(
               PositionQuery.match_all(),
               GameRecordQuery.match_all(),
               1
             )

    assert first_occurrence.position_id ==
             first_position_id

    later_record =
      GameRecord.new(
        "record-3",
        first_game_id
      )

    assert :ok =
             GameRecordRepository.insert(later_record)

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
             GameRecordRepository.insert(later_game_record)

    assert {
             :ok,
             [
               {
                 ^second,
                 second_occurrence
               }
             ],
             :done
           } =
             GameSearchRepository.next_query_page(
               cursor,
               10
             )

    assert second_occurrence.position_id ==
             first_position_id
  end

  test "match-none queries return an empty page without touching PostgreSQL" do
    {
      result,
      query_count
    } =
      query_count(fn ->
        GameSearchRepository.query_page(
          PositionQuery.match_all(),
          GameRecordQuery.match_none(),
          10
        )
      end)

    assert result ==
             {
               :ok,
               [],
               :done
             }

    assert query_count ==
             0
  end

  test "closing a stateless cursor does not invalidate it" do
    {
      _position_id,
      game_id
    } =
      stored_game(Position.starting_position())

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
             GameRecordRepository.insert(first)

    assert :ok =
             GameRecordRepository.insert(second)

    assert {
             :ok,
             [
               {
                 ^first,
                 _occurrence
               }
             ],
             cursor
           } =
             GameSearchRepository.query_page(
               PositionQuery.match_all(),
               GameRecordQuery.match_all(),
               1
             )

    assert :ok =
             GameSearchRepository.close_query(cursor)

    assert {
             :ok,
             [
               {
                 ^second,
                 _occurrence
               }
             ],
             :done
           } =
             GameSearchRepository.next_query_page(
               cursor,
               1
             )
  end

  def handle_query(_event, _measurements, _metadata, parent) do
    send(
      parent,
      :postgres_game_search_repository_query
    )

    :ok
  end

  defp stored_game(position) do
    {:ok, position_id} =
      PositionRepository.put(position)

    content =
      GameContent.new(position_id)

    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    {:ok, game_id} =
      GameRepository.put(
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
      :postgres_game_search_repository_query ->
        drain_query_count(count + 1)
    after
      0 ->
        count
    end
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
