defmodule Analysis.PgnImporterTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PgnImporter
  alias Analysis.PositionStore
  alias Chess.Notation.FEN
  alias Chess.Position
  alias OpenChessLab.Repo

  @sample_pgn """
  [Event "OpenChessLab sample"]
  [Site "Local demo"]
  [Date "2026.01.01"]
  [White "Alice Example"]
  [Black "Boris Example"]
  [Result "*"]

  1. e4 {A classical opening} e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 *
  """

  test "parses a main line and validates every SAN move" do
    assert {:ok, parsed} =
             PgnImporter.parse(@sample_pgn)

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

  test "parses a custom FEN starting position and preserves its move number" do
    fen =
      "4k3/8/8/8/8/8/4K3/7R w - - 12 37"

    pgn = """
    [SetUp "1"]
    [FEN "#{fen}"]

    37. Rh2 *
    """

    assert {:ok, parsed} =
             PgnImporter.parse(pgn)

    assert {:ok, fen_context} =
             FEN.parse(fen)

    assert parsed.initial_position ==
             fen_context.position

    assert parsed.start ==
             GameStart.new(37)

    assert length(parsed.moves) ==
             1

    assert parsed.final_position.side_to_move ==
             :black
  end

  test "rejects an invalid custom FEN starting position" do
    pgn = """
    [SetUp "1"]
    [FEN "this is not FEN"]

    1. e4
    """

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "Invalid FEN starting position"
              }}
  end

  test "rejects SetUp without a FEN starting position" do
    pgn = """
    [SetUp "1"]

    1. e4
    """

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "SetUp tag requires a FEN starting position"
              }}
  end

  test "rejects a FEN starting position without SetUp one" do
    fen =
      "4k3/8/8/8/8/8/4K3/7R w - - 12 37"

    pgn_without_setup = """
    [FEN "#{fen}"]

    37. Rh2 *
    """

    assert PgnImporter.parse(pgn_without_setup) ==
             {:error,
              {
                :invalid_pgn,
                "FEN starting position requires SetUp \"1\""
              }}

    pgn_with_setup_zero = """
    [SetUp "0"]
    [FEN "#{fen}"]

    37. Rh2 *
    """

    assert PgnImporter.parse(pgn_with_setup_zero) ==
             {:error,
              {
                :invalid_pgn,
                "FEN starting position requires SetUp \"1\""
              }}
  end

  test "rejects two headered games" do
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

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "Multiple games are not supported"
              }}
  end

  test "rejects two tagless games" do
    pgn = """
    1. e4 e5 1-0

    1. d4 d5 0-1
    """

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "Multiple games are not supported"
              }}
  end

  test "rejects a second game even when the first has no termination marker" do
    pgn = """
    1. e4 e5

    1. d4 d5
    """

    assert PgnImporter.parse(pgn) ==
             {:error,
              {
                :invalid_pgn,
                "Multiple games are not supported"
              }}
  end

  test "allows an explicit black move number inside one game" do
    assert {:ok, parsed} =
             PgnImporter.parse("1. e4 1... e5 2. Nf3 Nc6 *")

    assert length(parsed.moves) ==
             4
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

  test "durably imports a game from a custom FEN starting position" do
    record_id =
      unique_record_id()

    fen =
      "4k3/8/8/8/8/8/4K3/7R w - - 12 37"

    pgn = """
    [Event "Custom position"]
    [SetUp "1"]
    [FEN "#{fen}"]
    [Result "*"]

    37. Rh2 *
    """

    assert {:ok, record} =
             PgnImporter.import_game(
               record_id,
               pgn
             )

    assert GameRecord.start(record) ==
             GameStart.new(37)

    assert {
             :ok,
             ^record,
             content,
             occurrences
           } =
             GameRecords.load(record_id)

    assert length(GameContent.moves(content)) ==
             1

    assert Enum.map(
             occurrences,
             & &1.ply
           ) ==
             [
               0,
               1
             ]

    assert {:ok, expected} =
             FEN.parse(fen)

    assert {:ok, stored_initial_position} =
             PositionStore.get(GameContent.initial_position_id(content))

    assert stored_initial_position ==
             expected.position
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

  test "does not create a game record for multi-game PGN" do
    record_id =
      unique_record_id()

    pgn = """
    [Event "First"]

    1. e4 e5 1-0

    [Event "Second"]

    1. d4 d5 0-1
    """

    assert PgnImporter.import_game(
             record_id,
             pgn
           ) ==
             {:error,
              {
                :invalid_pgn,
                "Multiple games are not supported"
              }}

    assert GameRecords.get(record_id) ==
             :not_found
  end

  test "imports one durable PGN in one PostgreSQL transaction" do
    record_id =
      unique_record_id()

    pgn = """
    [Event "Single transaction"]

    1. e4 e5 2. Nf3 Nc6 *
    """

    queries =
      capture_queries(fn ->
        assert {:ok, _record} =
                 PgnImporter.import_game(
                   record_id,
                   pgn
                 )
      end)

    assert Enum.count(
             queries,
             &(&1 == "begin")
           ) ==
             1

    assert Enum.count(
             queries,
             &(&1 == "commit")
           ) ==
             1
  end

  test "rolls back the initial position when durable import fails" do
    record_id =
      "pgn-import-rejected-by-test-constraint"

    fen =
      "4k3/8/8/8/8/8/3K4/7R w - - 12 47"

    assert {:ok, fen_context} =
             FEN.parse(fen)

    assert PositionStore.find(fen_context.position) ==
             :not_found

    Repo.query!(
      """
      ALTER TABLE game_records
      ADD CONSTRAINT game_records_pgn_import_test_reject_record
      CHECK (
        record_id <> 'pgn-import-rejected-by-test-constraint'
      )
      """,
      []
    )

    on_exit(fn ->
      Repo.query!(
        """
        ALTER TABLE game_records
        DROP CONSTRAINT IF EXISTS game_records_pgn_import_test_reject_record
        """,
        []
      )
    end)

    pgn = """
    [Event "Rejected import"]
    [SetUp "1"]
    [FEN "#{fen}"]
    [Result "*"]

    47. Rh2 *
    """

    assert {
             :error,
             {
               :game_record_store,
               %Postgrex.Error{}
             }
           } =
             PgnImporter.import_game(
               record_id,
               pgn
             )

    assert PositionStore.find(fen_context.position) ==
             :not_found

    assert GameRecords.get(record_id) ==
             :not_found
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

  defp unique_record_id do
    "pgn-import-test-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end
end
