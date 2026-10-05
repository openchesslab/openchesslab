defmodule Analysis.GameRecordsPageTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PositionStore
  alias Chess.Position
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

    initial_position_id =
      PositionStore.append(Position.starting_position())

    content =
      GameContent.new(initial_position_id)

    %{
      content: content
    }
  end

  test "exposes paged durable game records through the application service",
       %{
         content: content
       } do
    assert {:ok, first} =
             GameRecords.create(
               "record-1",
               content,
               GameStart.standard(),
               %{
                 "event" => "First"
               }
             )

    assert {:ok, second} =
             GameRecords.create(
               "record-2",
               content,
               GameStart.standard(),
               %{
                 "event" => "Second"
               }
             )

    assert {:ok, third} =
             GameRecords.create(
               "record-3",
               content,
               GameStart.standard(),
               %{
                 "event" => "Third"
               }
             )

    assert {:ok, first_page} =
             GameRecords.page(limit: 2)

    assert Enum.map(
             first_page.entries,
             &GameRecord.id/1
           ) ==
             [
               GameRecord.id(first),
               GameRecord.id(second)
             ]

    refute is_nil(first_page.next)

    assert {:ok, second_page} =
             GameRecords.page(
               limit: 2,
               cursor: first_page.next
             )

    assert Enum.map(
             second_page.entries,
             &GameRecord.id/1
           ) ==
             [
               GameRecord.id(third)
             ]

    assert second_page.next ==
             nil
  end

  test "preserves page option validation from the durable store" do
    assert GameRecords.page([]) ==
             {:error, :missing_limit}

    assert GameRecords.page(limit: 0) ==
             {:error, :invalid_limit}

    assert GameRecords.page(
             limit: 10,
             cursor: make_ref()
           ) ==
             {:error, :invalid_cursor}

    assert GameRecords.page(:invalid) ==
             {:error, :invalid_page_options}
  end
end
