defmodule Analysis.PgnBatchImporterTest do
  use ExUnit.Case, async: true

  alias Analysis.GameStart
  alias Analysis.PgnBatchImporter

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
end
