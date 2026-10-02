defmodule Analysis.PostgresGameRecordRepositoryTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecordRepository.Postgres, as: GameRecordRepository
  alias Analysis.GameRepository.Postgres, as: GameRepository
  alias Analysis.GameStart
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

  test "reports ready when PostgreSQL is reachable" do
    assert GameRecordRepository.ready?()
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
             GameRecordRepository.insert(record)

    assert GameRecordRepository.get("record-1") ==
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
             GameRecordRepository.insert(first)

    assert GameRecordRepository.insert(second) ==
             {:error, :already_exists}

    assert GameRecordRepository.get("record-1") ==
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
          GameRecordRepository.insert(record)
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(
             results,
             &(&1 == :ok)
           ) == 1

    assert Enum.count(
             results,
             &(&1 == {:error, :already_exists})
           ) == 1

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
             GameRecordRepository.insert(record)

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_records
               """,
               []
             ).rows
  end

  test "pages records for one canonical game without duplicates or omissions" do
    game_id =
      stored_game_id()

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
             GameRecordRepository.records_page_by_game_id(
               game_id,
               2
             )

    assert %GameRecordRepository.Cursor{} =
             cursor

    assert {
             :ok,
             second_page,
             cursor
           } =
             GameRecordRepository.next_records_page(
               cursor,
               2
             )

    assert %GameRecordRepository.Cursor{} =
             cursor

    assert {
             :ok,
             third_page,
             :done
           } =
             GameRecordRepository.next_records_page(
               cursor,
               2
             )

    assert first_page ++ second_page ++ third_page ==
             records
  end

  test "does not include records inserted after a scan starts" do
    game_id =
      stored_game_id()

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
             [^first],
             cursor
           } =
             GameRecordRepository.records_page_by_game_id(
               game_id,
               1
             )

    third =
      GameRecord.new(
        "record-3",
        game_id
      )

    assert :ok =
             GameRecordRepository.insert(third)

    assert {
             :ok,
             [^second],
             :done
           } =
             GameRecordRepository.next_records_page(
               cursor,
               10
             )

    assert GameRecordRepository.get("record-3") ==
             {:ok, third}
  end

  test "returns an empty bounded page for a game without concrete records" do
    game_id =
      stored_game_id()

    assert GameRecordRepository.records_page_by_game_id(
             game_id,
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "returns not found for an unknown record id" do
    assert GameRecordRepository.get("missing-record") ==
             :not_found
  end

  test "rejects metadata that cannot be represented durably as JSON" do
    game_id =
      stored_game_id()

    record =
      apply(
        Kernel,
        :struct!,
        [
          GameRecord,
          [
            id: "record-1",
            game_id: game_id,
            start: GameStart.standard(),
            metadata: %{
              event: "Example"
            }
          ]
        ]
      )

    assert GameRecordRepository.insert(record) ==
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

  test "close_records is a no-op for stateless cursors" do
    game_id =
      stored_game_id()

    assert :ok =
             GameRecordRepository.insert(
               GameRecord.new(
                 "record-1",
                 game_id
               )
             )

    assert :ok =
             GameRecordRepository.insert(
               GameRecord.new(
                 "record-2",
                 game_id
               )
             )

    assert {
             :ok,
             [_record],
             cursor
           } =
             GameRecordRepository.records_page_by_game_id(
               game_id,
               1
             )

    assert :ok =
             GameRecordRepository.close_records(cursor)

    assert {
             :ok,
             [_record],
             :done
           } =
             GameRecordRepository.next_records_page(
               cursor,
               1
             )

    assert GameRecordRepository.next_records_page(
             make_ref(),
             1
           ) ==
             {:error, :cursor_not_found}
  end

  test "pages records matching metadata containment without duplicates or omissions" do
    game_id =
      stored_game_id()

    first =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "Wijk aan Zee"
        }
      )

    second =
      GameRecord.new(
        "record-2",
        game_id,
        %{
          "white" => "Other Player",
          "event" => "Wijk aan Zee"
        }
      )

    third =
      GameRecord.new(
        "record-3",
        game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "London"
        }
      )

    fourth =
      GameRecord.new(
        "record-4",
        game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "Oslo"
        }
      )

    for record <- [
          first,
          second,
          third,
          fourth
        ] do
      assert :ok =
               GameRecordRepository.insert(record)
    end

    query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             first_page,
             cursor
           } =
             GameRecordRepository.query_page(
               query,
               2
             )

    assert %GameRecordRepository.QueryCursor{} =
             cursor

    assert {
             :ok,
             second_page,
             :done
           } =
             GameRecordRepository.next_query_page(
               cursor,
               2
             )

    assert MapSet.new(first_page ++ second_page) ==
             MapSet.new([
               first,
               third,
               fourth
             ])
  end

  test "metadata query scan excludes records inserted after it starts" do
    game_id =
      stored_game_id()

    first =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "white" => "Magnus Carlsen"
        }
      )

    second =
      GameRecord.new(
        "record-2",
        game_id,
        %{
          "white" => "Magnus Carlsen"
        }
      )

    assert :ok =
             GameRecordRepository.insert(first)

    assert :ok =
             GameRecordRepository.insert(second)

    query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             [_first_page_record],
             cursor
           } =
             GameRecordRepository.query_page(
               query,
               1
             )

    later =
      GameRecord.new(
        "record-3",
        game_id,
        %{
          "white" => "Magnus Carlsen"
        }
      )

    assert :ok =
             GameRecordRepository.insert(later)

    assert {
             :ok,
             [_second_page_record],
             :done
           } =
             GameRecordRepository.next_query_page(
               cursor,
               10
             )

    assert GameRecordRepository.get("record-3") ==
             {:ok, later}
  end

  test "match none returns an empty bounded page" do
    assert GameRecordRepository.query_page(
             GameRecordQuery.match_none(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "filters bounded records for one canonical game by metadata" do
    game_id =
      stored_game_id()

    first =
      GameRecord.new(
        "record-1",
        game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "Wijk aan Zee"
        }
      )

    second =
      GameRecord.new(
        "record-2",
        game_id,
        %{
          "white" => "Other Player",
          "event" => "Wijk aan Zee"
        }
      )

    third =
      GameRecord.new(
        "record-3",
        game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "London"
        }
      )

    for record <- [
          first,
          second,
          third
        ] do
      assert :ok =
               GameRecordRepository.insert(record)
    end

    query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             [^first],
             cursor
           } =
             GameRecordRepository.records_page_by_game_id(
               game_id,
               query,
               1
             )

    assert %GameRecordRepository.Cursor{} =
             cursor

    assert {
             :ok,
             [^third],
             :done
           } =
             GameRecordRepository.next_records_page(
               cursor,
               10
             )
  end

  test "match none returns no records for a canonical game" do
    game_id =
      stored_game_id()

    assert GameRecordRepository.records_page_by_game_id(
             game_id,
             GameRecordQuery.match_none(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
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
      GameRepository.put(
        fingerprint,
        content,
        [position_id]
      )

    game_id
  end
end
