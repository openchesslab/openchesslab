defmodule Analysis.PostgresGameRecordStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionStore
  alias Chess.Position
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

  test "stores and loads a concrete game record" do
    game_id =
      stored_game_id()

    record =
      GameRecord.new(
        "record-1",
        game_id,
        GameStart.new(37),
        %{
          "white" => "White",
          "black" => "Black",
          "event" => "Example",
          "result" => "1-0"
        }
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert GameRecordStore.get("record-1") ==
             {:ok, record}

    assert [
             [
               "record-1",
               ^game_id,
               37,
               %{
                 "black" => "Black",
                 "event" => "Example",
                 "result" => "1-0",
                 "white" => "White"
               }
             ]
           ] =
             Repo.query!(
               """
               SELECT
                 record_id,
                 game_id,
                 fullmove_number,
                 metadata
               FROM game_records
               """,
               []
             ).rows
  end

  test "rejects duplicate logical record ids" do
    game_id =
      stored_game_id()

    first =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "event" => "First"
        }
      )

    second =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "event" => "Second"
        }
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert GameRecordStore.insert(second) ==
             {:error, :already_exists}

    assert GameRecordStore.get("record-1") ==
             {:ok, first}

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "concurrent inserts of the same record id create one record" do
    game_id =
      stored_game_id()

    record =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "event" => "Example"
        }
      )

    results =
      1..2
      |> Enum.map(fn _index ->
        Task.async(fn ->
          GameRecordStore.insert(record)
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(
             results,
             &(&1 == :ok)
           ) ==
             1

    assert Enum.count(
             results,
             &(&1 == {:error, :already_exists})
           ) ==
             1

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "enforces the canonical game foreign key" do
    record =
      GameRecord.new(
        "record-1",
        9_000_000_000,
        %{}
      )

    assert {:error, _reason} =
             GameRecordStore.insert(record)

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "returns not found for an unknown record id" do
    assert GameRecordStore.get("missing-record") ==
             :not_found
  end

  test "rejects metadata that cannot be represented durably as JSON" do
    game_id =
      stored_game_id()

    valid_record =
      GameRecord.new(
        "record-1",
        game_id
      )

    invalid_record =
      %{
        valid_record
        | metadata: %{
            event: "Example"
          }
      }

    assert GameRecordStore.insert(invalid_record) ==
             {:error, :invalid_metadata}

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "validates malformed game records before writing" do
    game_id =
      stored_game_id()

    valid_record =
      GameRecord.new(
        "record-1",
        game_id
      )

    assert GameRecordStore.insert(%{
             valid_record
             | id: ""
           }) ==
             {:error, :invalid_record_id}

    assert GameRecordStore.insert(%{
             valid_record
             | game_id: 0
           }) ==
             {:error, :invalid_game_id}

    assert GameRecordStore.insert(%{
             valid_record
             | start: %GameStart{
                 fullmove_number: 0
               }
           }) ==
             {:error, :invalid_fullmove_number}

    assert GameRecordStore.insert(:not_a_record) ==
             {:error, :invalid_game_record}

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "pages concrete game records without duplicates or omissions" do
    game_id =
      stored_game_id()

    first =
      record(
        "record-1",
        game_id
      )

    second =
      record(
        "record-2",
        game_id
      )

    third =
      record(
        "record-3",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert :ok =
             GameRecordStore.insert(third)

    assert {
             :ok,
             %GameRecordStore.Page{
               entries: [
                 ^first,
                 ^second
               ],
               next: cursor
             }
           } =
             GameRecordStore.page(limit: 2)

    assert %GameRecordStore.Cursor{} =
             cursor

    assert {
             :ok,
             %GameRecordStore.Page{
               entries: [
                 ^third
               ],
               next: nil
             }
           } =
             GameRecordStore.page(
               limit: 2,
               cursor: cursor
             )
  end

  test "does not include records added after a listing starts" do
    game_id =
      stored_game_id()

    first =
      record(
        "record-1",
        game_id
      )

    second =
      record(
        "record-2",
        game_id
      )

    third =
      record(
        "record-3",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert {
             :ok,
             %GameRecordStore.Page{
               entries: [
                 ^first
               ],
               next: cursor
             }
           } =
             GameRecordStore.page(limit: 1)

    assert :ok =
             GameRecordStore.insert(third)

    assert {
             :ok,
             %GameRecordStore.Page{
               entries: [
                 ^second
               ],
               next: nil
             }
           } =
             GameRecordStore.page(
               limit: 10,
               cursor: cursor
             )

    assert {
             :ok,
             %GameRecordStore.Page{
               entries: [
                 ^first,
                 ^second,
                 ^third
               ],
               next: nil
             }
           } =
             GameRecordStore.page(limit: 10)
  end

  test "returns an empty page when no records exist" do
    assert GameRecordStore.page(limit: 10) ==
             {
               :ok,
               %GameRecordStore.Page{
                 entries: [],
                 next: nil
               }
             }
  end

  test "requires a positive page limit" do
    assert GameRecordStore.page([]) ==
             {:error, :missing_limit}

    assert GameRecordStore.page(limit: 0) ==
             {:error, :invalid_limit}

    assert GameRecordStore.page(limit: -1) ==
             {:error, :invalid_limit}
  end

  test "rejects invalid page options and cursors" do
    assert GameRecordStore.page(:invalid) ==
             {:error, :invalid_page_options}

    assert GameRecordStore.page(
             limit: 10,
             cursor: make_ref()
           ) ==
             {:error, :invalid_cursor}
  end

  defp record(record_id, game_id) do
    GameRecord.new(
      record_id,
      game_id,
      %{
        "record" => record_id
      }
    )
  end

  defp stored_game_id do
    position_id =
      PositionStore.append(Position.starting_position())

    assert is_integer(position_id)
    assert position_id > 0

    content =
      GameContent.new(position_id)

    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    {:ok, game_id} =
      GameStore.put(
        fingerprint,
        content,
        [position_id]
      )

    game_id
  end
end
