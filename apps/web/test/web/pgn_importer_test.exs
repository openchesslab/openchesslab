defmodule Web.PgnImporterTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.PositionStore
  alias Chess.Position
  alias Web.DemoData
  alias Web.PgnImporter

  test "parses the sample main line and validates every SAN move" do
    assert {:ok, parsed} =
             PgnImporter.parse(DemoData.game("demo-ruy-lopez").pgn)

    assert length(parsed.moves) ==
             10

    assert parsed.headers["White"] ==
             "Alice Example"

    assert parsed.final_position.side_to_move ==
             :white
  end

  test "reports invalid SAN rather than inventing a move" do
    assert {:error,
            {
              :invalid_pgn,
              message
            }} =
             PgnImporter.parse("1. e4 e5 2. ThisIsNotSAN")

    assert message =~
             "Could not parse move"
  end

  test "rejects custom starting positions explicitly" do
    pgn = """
    [SetUp "1"]
    [FEN "8/8/8/8/8/8/4K3/7k w - - 0 1"]

    1. Kf3
    """

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "Custom starting positions are not supported"
              }}
  end

  test "imports a PGN as a durable concrete game record" do
    record_id =
      unique_record_id()

    pgn = """
    [Event "Candidates"]
    [White "Alice Example"]
    [Black "Boris Example"]
    [WhiteElo "2410"]
    [Result "1-0"]

    1. e4 e5 2. Nf3 Nc6 1-0
    """

    assert {:ok, record} =
             PgnImporter.import_game(
               record_id,
               pgn
             )

    assert GameRecord.id(record) ==
             record_id

    assert GameRecord.metadata(record) ==
             %{
               "black" => "Boris Example",
               "event" => "Candidates",
               "result" => "1-0",
               "white" => "Alice Example",
               "white_elo" => "2410"
             }

    assert {
             :ok,
             ^record,
             content,
             occurrences
           } =
             GameRecords.load(record_id)

    assert length(GameContent.moves(content)) ==
             4

    assert Enum.map(
             occurrences,
             & &1.ply
           ) ==
             [
               0,
               1,
               2,
               3,
               4
             ]

    assert {:ok, initial_position} =
             PositionStore.get(GameContent.initial_position_id(content))

    assert initial_position ==
             Position.starting_position()
  end

  test "does not create a game record for invalid PGN" do
    record_id =
      unique_record_id()

    assert {:error,
            {
              :invalid_pgn,
              _message
            }} =
             PgnImporter.import_game(
               record_id,
               "1. e4 e5 2. ThisIsNotSAN"
             )

    assert GameRecords.get(record_id) ==
             :not_found
  end

  defp unique_record_id do
    "pgn-import-test-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end
end
