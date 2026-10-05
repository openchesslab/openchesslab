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

    assert GameRecordStore.get(record_id) ==
             {:ok, first}

    assert GameRecordStore.get(second_record_id) ==
             {:ok, second}

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               WHERE game_id = $1
               """,
               [game_id]
             ).rows
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

  test "rolls back canonical writes when concrete record persistence fails",
       %{
         initial_position_id: initial_position_id
       } do
    record_id =
      "record-rejected-by-test-constraint"

    Repo.query!(
      """
      ALTER TABLE game_records
      ADD CONSTRAINT game_records_test_reject_record
      CHECK (
        record_id <> 'record-rejected-by-test-constraint'
      )
      """,
      []
    )

    on_exit(fn ->
      Repo.query!(
        """
        ALTER TABLE game_records
        DROP CONSTRAINT IF EXISTS game_records_test_reject_record
        """,
        []
      )
    end)

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

    assert {
             :error,
             {
               :game_record_store,
               %Postgrex.Error{}
             }
           } =
             GameRecords.create(
               record_id,
               content,
               GameStart.standard(),
               %{
                 "event" => "Example"
               }
             )

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

  test "concurrent creates with the same record id keep only one aggregate",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
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

    assert apply(
             GameRecords,
             :create,
             [
               123,
               content,
               GameStart.standard(),
               %{}
             ]
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
  end

  test "rejects invalid metadata before canonical game creation",
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

    assert apply(
             GameRecords,
             :create,
             [
               record_id,
               content,
               GameStart.standard(),
               %{
                 event: "Invalid"
               }
             ]
           ) ==
             {:error, :invalid_metadata}

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
  end

  test "does not query for an existing record before creating a new one",
       %{
         record_id: record_id,
         initial_position_id: initial_position_id
       } do
    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4")
        ]
      )

    queries =
      capture_queries(fn ->
        assert {:ok, _record} =
                 GameRecords.create(
                   record_id,
                   content,
                   GameStart.standard(),
                   %{}
                 )
      end)

    refute Enum.any?(
             queries,
             fn query ->
               normalized =
                 query
                 |> String.replace(
                   ~r/\s+/,
                   " "
                 )
                 |> String.trim()

               String.starts_with?(
                 normalized,
                 "SELECT record_id, game_id, fullmove_number, metadata FROM game_records WHERE record_id = $1"
               )
             end
           )
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp capture_queries(fun) do
    telemetry_prefix =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)

    event =
      telemetry_prefix ++
        [:query]

    handler_id =
      {
        __MODULE__,
        make_ref()
      }

    parent =
      self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, _measurements, metadata, parent ->
          send(
            parent,
            {
              :captured_query,
              metadata.query
            }
          )
        end,
        parent
      )

    try do
      fun.()
      drain_queries([])
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(queries) do
    receive do
      {
        :captured_query,
        query
      } ->
        drain_queries([query | queries])
    after
      0 ->
        Enum.reverse(queries)
    end
  end
end
