defmodule Analysis.GameRecordsTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameRecordStore
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  defmodule BarrierGameRecordRepository do
    @moduledoc false

    @behaviour Analysis.GameRecordRepository

    alias Analysis.GameRecordRepository.Postgres

    @impl true
    def ready? do
      Postgres.ready?()
    end

    @impl true
    def insert(record) do
      Postgres.insert(record)
    end

    @impl true
    def get(record_id) do
      result =
        Postgres.get(record_id)

      case Application.get_env(
             :analysis,
             :game_record_get_barrier
           ) do
        pid when is_pid(pid) ->
          send(
            pid,
            {
              :game_record_get_checked,
              self(),
              result
            }
          )

          receive do
            :continue_game_record_get ->
              result
          end

        _other ->
          result
      end
    end

    @impl true
    def records_page_by_game_id(game_id, page_size) do
      Postgres.records_page_by_game_id(
        game_id,
        page_size
      )
    end

    @impl true
    def next_records_page(cursor, page_size) do
      Postgres.next_records_page(
        cursor,
        page_size
      )
    end

    @impl true
    def close_records(cursor) do
      Postgres.close_records(cursor)
    end
  end

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

    record_id =
      "record-#{System.unique_integer([:positive])}"

    initial_position_id =
      PositionStore.append(Position.starting_position())

    %{
      record_id: record_id,
      initial_position_id: initial_position_id
    }
  end

  test "creates a durable concrete game record backed by canonical game content",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    start =
      GameStart.new(37)

    metadata = %{
      "white" => "White",
      "black" => "Black",
      "event" => "Example"
    }

    assert {:ok, record} =
             GameRecords.create(
               record_id,
               content,
               start,
               metadata
             )

    assert GameRecord.id(record) ==
             record_id

    assert GameRecord.start(record) ==
             start

    assert GameRecord.metadata(record) ==
             metadata

    assert GameRecordStore.get(record_id) ==
             {:ok, record}

    assert {:ok, ^content, occurrences} =
             GameStore.load(GameRecord.game_id(record))

    assert Enum.map(
             occurrences,
             & &1.ply
           ) ==
             [0, 1, 2]

    assert occurrences
           |> hd()
           |> Map.fetch!(:position_id) ==
             initial_position_id

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               WHERE record_id = $1
               """,
               [record_id]
             ).rows
  end

  test "reuses canonical game content for different durable concrete records",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    second_record_id =
      "#{record_id}-second"

    assert {:ok, first} =
             GameRecords.create(
               record_id,
               content,
               GameStart.standard(),
               %{
                 "event" => "London"
               }
             )

    assert {:ok, second} =
             GameRecords.create(
               second_record_id,
               content,
               GameStart.standard(),
               %{
                 "event" => "Amsterdam"
               }
             )

    assert GameRecord.id(first) !=
             GameRecord.id(second)

    assert GameRecord.game_id(first) ==
             GameRecord.game_id(second)

    game_id =
      GameRecord.game_id(first)

    assert {
             :ok,
             records,
             :done
           } =
             GameRecordStore.records_page_by_game_id(
               game_id,
               10
             )

    assert records ==
             [
               first,
               second
             ]

    assert Enum.all?(
             records,
             &(GameRecord.game_id(&1) ==
                 game_id)
           )
  end

  test "rejects an existing concrete record before canonicalizing another game",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    first_content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4")
        ]
      )

    assert {:ok, record} =
             GameRecords.create(
               record_id,
               first_content,
               GameStart.standard(),
               %{}
             )

    other_content =
      GameContent.new(
        initial_position_id,
        [
          move("d2", "d4")
        ]
      )

    assert {:ok, other_fingerprint} =
             GameFingerprint.for_content(other_content)

    assert GameRecords.create(
             record_id,
             other_content,
             GameStart.standard(),
             %{}
           ) ==
             {:error, :already_exists}

    assert GameStore.find(
             other_fingerprint,
             other_content
           ) ==
             :not_found

    assert GameRecordStore.get(record_id) ==
             {:ok, record}
  end

  test "rejects canonical content containing an illegal move",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4"),
          move("e7", "e4")
        ]
      )

    assert GameRecords.create(
             record_id,
             content,
             GameStart.standard(),
             %{}
           ) ==
             {:error,
              {
                :invalid_game,
                {
                  :illegal_move,
                  2
                }
              }}

    assert GameRecordStore.get(record_id) ==
             :not_found
  end

  test "rejects canonical content whose initial position is missing",
       %{
         record_id: record_id
       } do
    content =
      GameContent.new(999_999_999)

    assert GameRecords.create(
             record_id,
             content,
             GameStart.standard(),
             %{}
           ) ==
             {:error,
              {
                :invalid_game,
                {
                  :position_not_found,
                  999_999_999
                }
              }}

    assert GameRecordStore.get(record_id) ==
             :not_found
  end

  test "rejects invalid canonical content before writing a record",
       %{
         record_id: record_id
       } do
    content =
      GameContent.new(0)

    assert GameRecords.create(
             record_id,
             content,
             GameStart.standard(),
             %{}
           ) ==
             {:error,
              {
                :invalid_game,
                :invalid_initial_position_id
              }}

    assert GameRecordStore.get(record_id) ==
             :not_found
  end

  test "gets a durable game record",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(initial_position_id)

    assert {:ok, record} =
             GameRecords.create(
               record_id,
               content,
               GameStart.standard(),
               %{}
             )

    assert GameRecords.get(record_id) ==
             {:ok, record}
  end

  test "loads a concrete game with canonical content and occurrences",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    assert {:ok, record} =
             GameRecords.create(
               record_id,
               content,
               GameStart.standard(),
               %{
                 "event" => "Example"
               }
             )

    assert {
             :ok,
             ^record,
             ^content,
             occurrences
           } =
             GameRecords.load(record_id)

    assert Enum.map(
             occurrences,
             & &1.ply
           ) ==
             [0, 1, 2]

    assert occurrences
           |> Enum.map(& &1.position_id)
           |> hd() ==
             initial_position_id
  end

  test "returns not_found when loading an unknown game record" do
    assert GameRecords.load("missing-game-record") ==
             :not_found
  end

  test "pages concrete game records for position occurrences without duplicates or omissions" do
    starting_position =
      Position.starting_position()

    position_id =
      PositionStore.append(starting_position)

    {:ok, middle_position} =
      Position.apply_move(
        starting_position,
        move("g1", "f3")
      )

    middle_position_id =
      PositionStore.append(middle_position)

    {:ok, other_initial_position} =
      Position.apply_move(
        starting_position,
        move("e2", "e4")
      )

    other_initial_position_id =
      PositionStore.append(other_initial_position)

    first_content =
      GameContent.new(
        position_id,
        [
          move("g1", "f3"),
          move("g8", "f6")
        ]
      )

    second_content =
      GameContent.new(
        other_initial_position_id,
        [
          move("e2", "e4")
        ]
      )

    assert {:ok, first_fingerprint} =
             GameFingerprint.for_content(first_content)

    assert {:ok, second_fingerprint} =
             GameFingerprint.for_content(second_content)

    assert {:ok, first_game_id} =
             GameStore.put(
               first_fingerprint,
               first_content,
               [
                 position_id,
                 middle_position_id,
                 position_id
               ]
             )

    assert {:ok, second_game_id} =
             GameStore.put(
               second_fingerprint,
               second_content,
               [
                 other_initial_position_id,
                 position_id
               ]
             )

    first_record =
      GameRecord.new(
        "record-#{unique_id()}",
        first_game_id
      )

    second_record =
      GameRecord.new(
        "record-#{unique_id()}",
        first_game_id
      )

    third_record =
      GameRecord.new(
        "record-#{unique_id()}",
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
             GameRecords.occurrences_page_by_position_id(
               position_id,
               2
             )

    assert length(first_page) ==
             2

    assert {
             :ok,
             second_page,
             cursor
           } =
             GameRecords.next_occurrences_page(
               cursor,
               2
             )

    assert length(second_page) ==
             2

    assert {
             :ok,
             third_page,
             :done
           } =
             GameRecords.next_occurrences_page(
               cursor,
               2
             )

    assert length(third_page) ==
             1

    matches =
      first_page ++
        second_page ++
        third_page

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
                 position_id
               },
               {
                 second_record,
                 first_game_id,
                 0,
                 position_id
               },
               {
                 first_record,
                 first_game_id,
                 2,
                 position_id
               },
               {
                 second_record,
                 first_game_id,
                 2,
                 position_id
               },
               {
                 third_record,
                 second_game_id,
                 1,
                 position_id
               }
             ])
  end

  test "returns an empty occurrence page for an unknown position" do
    assert GameRecords.occurrences_page_by_position_id(
             unique_id(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "closing an unfinished concrete occurrence cursor is a no-op for stateless repositories" do
    position_id =
      PositionStore.append(Position.starting_position())

    content =
      GameContent.new(position_id)

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [position_id]
             )

    first =
      GameRecord.new(
        "record-#{unique_id()}",
        game_id
      )

    second =
      GameRecord.new(
        "record-#{unique_id()}",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

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
             GameRecords.occurrences_page_by_position_id(
               position_id,
               1
             )

    assert :ok =
             GameRecords.close_occurrences(cursor)

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
             GameRecords.next_occurrences_page(
               cursor,
               1
             )
  end

  test "rolls back canonical writes when concrete record persistence fails",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    move =
      move(
        "e2",
        "e4"
      )

    content =
      GameContent.new(
        initial_position_id,
        [move]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, resulting_position} =
             Position.apply_move(
               Position.starting_position(),
               move
             )

    assert GameRecords.create(
             record_id,
             content,
             GameStart.standard(),
             %{
               event: "Invalid durable metadata"
             }
           ) ==
             {:error,
              {
                :game_record_store,
                :invalid_metadata
              }}

    assert GameRecordStore.get(record_id) ==
             :not_found

    assert GameStore.find(
             fingerprint,
             content
           ) ==
             :not_found

    assert PositionStore.find(resulting_position) ==
             :not_found

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_occurrences
               """,
               []
             ).rows

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows
  end

  test "concurrent creates with the same record id roll back the losing canonical writes",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    previous_repository =
      Application.get_env(
        :analysis,
        :game_record_repository,
        :not_configured
      )

    previous_barrier =
      Application.get_env(
        :analysis,
        :game_record_get_barrier,
        :not_configured
      )

    on_exit(fn ->
      restore_env(
        :game_record_repository,
        previous_repository
      )

      restore_env(
        :game_record_get_barrier,
        previous_barrier
      )
    end)

    Application.put_env(
      :analysis,
      :game_record_repository,
      BarrierGameRecordRepository
    )

    Application.put_env(
      :analysis,
      :game_record_get_barrier,
      self()
    )

    first_move =
      move(
        "e2",
        "e4"
      )

    second_move =
      move(
        "d2",
        "d4"
      )

    first_content =
      GameContent.new(
        initial_position_id,
        [first_move]
      )

    second_content =
      GameContent.new(
        initial_position_id,
        [second_move]
      )

    assert {:ok, first_resulting_position} =
             Position.apply_move(
               Position.starting_position(),
               first_move
             )

    assert {:ok, second_resulting_position} =
             Position.apply_move(
               Position.starting_position(),
               second_move
             )

    first_task =
      Task.async(fn ->
        GameRecords.create(
          record_id,
          first_content,
          GameStart.standard(),
          %{
            "source" => "first"
          }
        )
      end)

    second_task =
      Task.async(fn ->
        GameRecords.create(
          record_id,
          second_content,
          GameStart.standard(),
          %{
            "source" => "second"
          }
        )
      end)

    assert_receive {
      :game_record_get_checked,
      first_waiting_pid,
      :not_found
    }

    assert_receive {
      :game_record_get_checked,
      second_waiting_pid,
      :not_found
    }

    refute first_waiting_pid ==
             second_waiting_pid

    Application.delete_env(
      :analysis,
      :game_record_get_barrier
    )

    send(
      first_waiting_pid,
      :continue_game_record_get
    )

    send(
      second_waiting_pid,
      :continue_game_record_get
    )

    results =
      Task.await_many(
        [
          first_task,
          second_task
        ],
        5_000
      )

    assert Enum.count(
             results,
             fn
               {:ok, %GameRecord{}} ->
                 true

               _other ->
                 false
             end
           ) ==
             1

    assert Enum.count(
             results,
             &(&1 == {:error, :already_exists})
           ) ==
             1

    assert {:ok, stored_record} =
             GameRecordStore.get(record_id)

    assert {
             :ok,
             stored_content,
             occurrences
           } =
             GameStore.load(GameRecord.game_id(stored_record))

    assert length(occurrences) ==
             2

    case GameRecord.metadata(stored_record) do
      %{
        "source" => "first"
      } ->
        assert stored_content ==
                 first_content

        assert {:ok, _position_id} =
                 PositionStore.find(first_resulting_position)

        assert PositionStore.find(second_resulting_position) ==
                 :not_found

      %{
        "source" => "second"
      } ->
        assert stored_content ==
                 second_content

        assert {:ok, _position_id} =
                 PositionStore.find(second_resulting_position)

        assert PositionStore.find(first_resulting_position) ==
                 :not_found
    end

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_occurrences
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows
  end

  test "rejects an invalid record id before canonical game creation",
       %{
         initial_position_id: initial_position_id
       } do
    move =
      move(
        "e2",
        "e4"
      )

    content =
      GameContent.new(
        initial_position_id,
        [move]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, resulting_position} =
             Position.apply_move(
               Position.starting_position(),
               move
             )

    assert GameRecords.create(
             "",
             content,
             GameStart.standard(),
             %{}
           ) ==
             {:error, :invalid_record_id}

    assert GameStore.find(
             fingerprint,
             content
           ) ==
             :not_found

    assert PositionStore.find(resulting_position) ==
             :not_found

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows

    assert GameRecords.create(
             123,
             content,
             GameStart.standard(),
             %{}
           ) ==
             {:error, :invalid_record_id}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp unique_id do
    10_000_000_000 +
      System.unique_integer([
        :positive,
        :monotonic
      ])
  end

  defp restore_env(key, :not_configured) do
    Application.delete_env(
      :analysis,
      key
    )
  end

  defp restore_env(key, value) do
    Application.put_env(
      :analysis,
      key,
      value
    )
  end
end
