defmodule Analysis.GameRecordsTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
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

    assert GameStore.get(GameRecord.game_id(record)) ==
             {:ok, content}

    assert {:ok, occurrences} =
             GameStore.occurrences(GameRecord.game_id(record))

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

  defp move(
         from,
         to
       ) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
