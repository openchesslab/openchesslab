defmodule Analysis.PgnBatchImporterTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PgnBatchImporter
  alias Analysis.PgnImporter

  test "parses headered games in source order" do
    pgn = """
    [Event "First"]
    [White "Alice"]
    [Black "Bob"]
    [Result "1-0"]

    1. e4 e5 1-0

    [Event "Second"]
    [White "Carol"]
    [Black "Dave"]
    [Result "0-1"]

    1. d4 d5 0-1
    """

    assert {:ok, [first, second]} =
             PgnBatchImporter.parse(pgn)

    assert first.headers["Event"] ==
             "First"

    assert first.headers["White"] ==
             "Alice"

    assert length(first.moves) ==
             2

    assert second.headers["Event"] ==
             "Second"

    assert second.headers["White"] ==
             "Carol"

    assert length(second.moves) ==
             2
  end

  test "uses the single-game parser for custom starting positions" do
    pgn = """
    [Event "Standard"]
    [Result "*"]

    1. e4 *

    [Event "Custom"]
    [SetUp "1"]
    [FEN "4k3/8/8/8/8/8/4K3/7R w - - 12 37"]
    [Result "*"]

    37. Rh2 *
    """

    assert {:ok, [standard, custom]} =
             PgnBatchImporter.parse(pgn)

    assert standard.start ==
             GameStart.standard()

    assert custom.start ==
             GameStart.new(37)

    assert custom.headers["Event"] ==
             "Custom"

    assert length(custom.moves) ==
             1
  end

  test "reports which game in the batch is invalid" do
    pgn = """
    [Event "Valid"]

    1. e4 e5 *

    [Event "Broken"]

    1. d4 ThisIsNotSAN *
    """

    assert {:error,
            {
              :invalid_game,
              2,
              {
                :invalid_pgn,
                message
              }
            }} =
             PgnBatchImporter.parse(pgn)

    assert message =~
             "Could not parse move"
  end

  test "starts a new game at headers even without a termination marker" do
    pgn = """
    [Event "First"]

    1. e4 e5

    [Event "Second"]

    1. d4 d5 *
    """

    assert {:ok, [first, second]} =
             PgnBatchImporter.parse(pgn)

    assert first.headers["Event"] ==
             "First"

    assert length(first.moves) ==
             2

    assert second.headers["Event"] ==
             "Second"

    assert length(second.moves) ==
             2
  end

  test "requires tag-pair sections at the batch boundary" do
    assert PgnBatchImporter.parse("1. e4 e5 *") ==
             {:error, :game_headers_required}
  end

  test "rejects an empty batch" do
    assert PgnBatchImporter.parse(" \n\n ") ==
             {:error, :empty_batch}
  end

  test "durably imports parsed games using caller supplied record IDs" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    pgn = """
    [Event "First"]
    [White "Alice"]
    [Black "Bob"]

    1. e4 e5 *

    [Event "Second"]
    [White "Carol"]
    [Black "Dave"]

    1. d4 d5 *
    """

    assert {:ok, [first, second]} =
             PgnBatchImporter.import_games(
               [
                 first_id,
                 second_id
               ],
               pgn
             )

    assert GameRecord.id(first) ==
             first_id

    assert GameRecord.id(second) ==
             second_id

    assert GameRecord.metadata(first)["event"] ==
             "First"

    assert GameRecord.metadata(second)["event"] ==
             "Second"

    assert {:ok, ^first, _content, _occurrences} =
             GameRecords.load(first_id)

    assert {:ok, ^second, _content, _occurrences} =
             GameRecords.load(second_id)
  end

  test "does not persist any games when parsing the batch fails" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    pgn = """
    [Event "Valid"]

    1. e4 e5 *

    [Event "Broken"]

    1. d4 ThisIsNotSAN *
    """

    assert {:error,
            {
              :invalid_game,
              2,
              {
                :invalid_pgn,
                _message
              }
            }} =
             PgnBatchImporter.import_games(
               [
                 first_id,
                 second_id
               ],
               pgn
             )

    assert GameRecords.get(first_id) ==
             :not_found

    assert GameRecords.get(second_id) ==
             :not_found
  end

  test "requires exactly one record ID per game before persistence" do
    record_id =
      unique_record_id()

    pgn = """
    [Event "First"]

    1. e4 *

    [Event "Second"]

    1. d4 *
    """

    assert PgnBatchImporter.import_games(
             [record_id],
             pgn
           ) ==
             {:error,
              {
                :record_id_count_mismatch,
                2,
                1
              }}

    assert GameRecords.get(record_id) ==
             :not_found
  end

  test "rejects duplicate record IDs before persistence" do
    record_id =
      unique_record_id()

    pgn = """
    [Event "First"]

    1. e4 *

    [Event "Second"]

    1. d4 *
    """

    assert PgnBatchImporter.import_games(
             [
               record_id,
               record_id
             ],
             pgn
           ) ==
             {:error,
              {
                :duplicate_record_id,
                2
              }}

    assert GameRecords.get(record_id) ==
             :not_found
  end

  test "keeps the successful prefix when persistence of a later game fails" do
    first_id =
      unique_record_id()

    existing_id =
      unique_record_id()

    assert {:ok, existing} =
             PgnImporter.import_game(
               existing_id,
               """
               [Event "Existing"]

               1. c4 *
               """
             )

    pgn = """
    [Event "First"]

    1. e4 *

    [Event "Second"]

    1. d4 *
    """

    assert PgnBatchImporter.import_games(
             [
               first_id,
               existing_id
             ],
             pgn
           ) ==
             {:error,
              {
                :import_failed,
                2,
                :already_exists
              }}

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert GameRecord.id(first) ==
             first_id

    assert GameRecord.metadata(first)["event"] ==
             "First"

    assert GameRecords.get(existing_id) ==
             {:ok, existing}
  end

  test "streams durable imports one game at a time" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    record_ids = %{
      1 => first_id,
      2 => second_id
    }

    lines =
      """
      [Event "First"]

      1. e4 e5 *

      [Event "Second"]

      1. d4 d5 *
      """
      |> String.split(
        ~r/\R/,
        trim: false
      )
      |> Stream.map(& &1)

    assert PgnBatchImporter.import_stream(
             lines,
             &Map.fetch!(record_ids, &1)
           ) ==
             {:ok, 2}

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert {:ok, second} =
             GameRecords.get(second_id)

    assert GameRecord.metadata(first)["event"] ==
             "First"

    assert GameRecord.metadata(second)["event"] ==
             "Second"
  end

  test "streaming import keeps the successful prefix when a later game is invalid" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    record_ids = %{
      1 => first_id,
      2 => second_id
    }

    lines =
      """
      [Event "First"]

      1. e4 e5 *

      [Event "Broken"]

      1. d4 ThisIsNotSAN *
      """
      |> String.split(
        ~r/\R/,
        trim: false
      )
      |> Stream.map(& &1)

    assert {:error,
            {
              :invalid_game,
              2,
              {
                :invalid_pgn,
                message
              }
            }} =
             PgnBatchImporter.import_stream(
               lines,
               &Map.fetch!(record_ids, &1)
             )

    assert message =~
             "Could not parse move"

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert GameRecord.metadata(first)["event"] ==
             "First"

    assert GameRecords.get(second_id) ==
             :not_found
  end

  test "streaming import reports an invalid caller supplied record ID at its game index" do
    first_id =
      unique_record_id()

    lines =
      """
      [Event "First"]

      1. e4 *

      [Event "Second"]

      1. d4 *
      """
      |> String.split(
        ~r/\R/,
        trim: false
      )
      |> Stream.map(& &1)

    assert PgnBatchImporter.import_stream(
             lines,
             fn
               1 -> first_id
               2 -> ""
             end
           ) ==
             {:error,
              {
                :invalid_record_id,
                2
              }}

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert GameRecord.metadata(first)["event"] ==
             "First"
  end

  test "streaming import stops consuming input after a failed game" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    test_pid =
      self()

    lines =
      [
        "[Event \"First\"]",
        "",
        "1. e4 *",
        "",
        "[Event \"Broken\"]",
        "",
        "1. d4 ThisIsNotSAN *",
        "",
        "[Event \"Third\"]",
        "1. c4 *"
      ]
      |> Stream.map(fn line ->
        if line == "1. c4 *" do
          send(
            test_pid,
            :third_game_movetext_consumed
          )
        end

        line
      end)

    assert {:error,
            {
              :invalid_game,
              2,
              {
                :invalid_pgn,
                _message
              }
            }} =
             PgnBatchImporter.import_stream(
               lines,
               fn
                 1 -> first_id
                 2 -> second_id
               end
             )

    refute_received :third_game_movetext_consumed

    assert {:ok, _first} =
             GameRecords.get(first_id)

    assert GameRecords.get(second_id) ==
             :not_found
  end

  defp unique_record_id do
    "pgn-batch-import-test-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end
end
