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

  setup do
    record_id =
      "record-#{System.unique_integer([:positive])}"

    initial_position_id =
      PositionStore.append(Position.starting_position())

    %{
      record_id: record_id,
      initial_position_id: initial_position_id
    }
  end

  test "creates a concrete game record backed by canonical game content",
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
      white: "White",
      black: "Black",
      event: "Example"
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
  end

  test "reuses canonical game content for different concrete records",
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
                 event: "London"
               }
             )

    assert {:ok, second} =
             GameRecords.create(
               second_record_id,
               content,
               GameStart.standard(),
               %{
                 event: "Amsterdam"
               }
             )

    assert GameRecord.id(first) !=
             GameRecord.id(second)

    assert GameRecord.game_id(first) ==
             GameRecord.game_id(second)

    game_id =
      GameRecord.game_id(first)

    records =
      GameRecords.list_by_game_id(game_id)

    assert first in records
    assert second in records

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

    cardinality =
      GameStore.cardinality()

    other_content =
      GameContent.new(
        initial_position_id,
        [
          move("d2", "d4")
        ]
      )

    assert GameRecords.create(
             record_id,
             other_content,
             GameStart.standard(),
             %{}
           ) ==
             {:error, :already_exists}

    assert GameStore.cardinality() ==
             cardinality

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

  test "gets a stored game record",
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

  test "lists stored game records",
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

    assert record in GameRecords.list()
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
                 event: "Example"
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
           ) == [0, 1, 2]

    assert Enum.map(
             occurrences,
             & &1.position_id
           )
           |> hd() ==
             initial_position_id
  end

  test "returns not_found when loading an unknown game record" do
    assert GameRecords.load("missing-game-record") ==
             :not_found
  end

  test "reports a missing canonical game when loading a game record",
       %{
         record_id: record_id
       } do
    missing_game_id =
      unique_id()

    record =
      GameRecord.new(
        record_id,
        missing_game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert GameRecords.load(record_id) ==
             {:error,
              {
                :game_not_found,
                missing_game_id
              }}
  end

  test "propagates invalid canonical occurrences when loading a game record",
       %{
         record_id: record_id
       } do
    initial_position_id =
      unique_id()

    content =
      GameContent.new(
        initial_position_id,
        [
          move("e2", "e4")
        ]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [
                 initial_position_id
               ]
             )

    record =
      GameRecord.new(
        record_id,
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert GameRecords.load(record_id) ==
             {:error,
              {
                :game_store,
                :invalid_occurrences
              }}
  end

  test "lists concrete game records for a position occurrence" do
    position_id =
      unique_id()

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
        game_id,
        %{
          event: "London"
        }
      )

    second =
      GameRecord.new(
        "record-#{unique_id()}",
        game_id,
        %{
          event: "Amsterdam"
        }
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert {
             :ok,
             matches
           } =
             GameRecords.list_occurrences_by_position_id(position_id)

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
                 first,
                 game_id,
                 0,
                 position_id
               },
               {
                 second,
                 game_id,
                 0,
                 position_id
               }
             ])
  end

  test "preserves repeated occurrences of a position within a game" do
    position_id =
      unique_id()

    middle_position_id =
      unique_id()

    content =
      GameContent.new(
        position_id,
        [
          move("g1", "f3"),
          move("g8", "f6")
        ]
      )

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [
                 position_id,
                 middle_position_id,
                 position_id
               ]
             )

    record =
      GameRecord.new(
        "record-#{unique_id()}",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert {
             :ok,
             matches
           } =
             GameRecords.list_occurrences_by_position_id(position_id)

    record_matches =
      Enum.filter(
        matches,
        fn {matched_record, _occurrence} ->
          matched_record ==
            record
        end
      )

    assert MapSet.new(
             Enum.map(
               record_matches,
               fn {_record, occurrence} ->
                 {
                   occurrence.game_id,
                   occurrence.ply,
                   occurrence.position_id
                 }
               end
             )
           ) ==
             MapSet.new([
               {
                 game_id,
                 0,
                 position_id
               },
               {
                 game_id,
                 2,
                 position_id
               }
             ])
  end

  test "returns no concrete occurrences for an unknown position" do
    assert GameRecords.list_occurrences_by_position_id(unique_id()) ==
             {:ok, []}
  end

  defp move(
         from,
         to
       ) do
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
end
