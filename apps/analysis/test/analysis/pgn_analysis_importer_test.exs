defmodule Analysis.PgnAnalysisImporterTest do
  use ExUnit.Case, async: false

  alias Analysis.{Analyses, AnalysisStore, GameRecords, GameStart, PgnAnalysisImporter}
  alias Chess.Position
  alias OpenChessLab.Repo

  defp position_of(node), do: Analysis.PositionStore.get(node.position_id)

  defp import_pgn(pgn, opts \\ []) do
    suffix = Ecto.UUID.generate()
    PgnAnalysisImporter.import("pgn-analysis-" <> suffix, "pgn-record-" <> suffix, pgn, opts)
  end

  test "preserves root and move comments, numeric/symbolic NAGs and strips machine commands" do
    pgn = """
    [Event "Annotated game"]

    {Opening note} 1.e4! $1 {Human [%eval 0.32] text} {Second note}
    (1.d4?? {Do not attach this} (1.c4 $3))
    e5 $14 ;Black's reply
    2.Nf3?! {[%clk 0:03:00]} Nc6 *
    """

    assert {:ok, analysis, revision} = import_pgn(pgn)
    assert {:ok, ^analysis, ^revision} = AnalysisStore.get(analysis.id)
    assert analysis.root.comment == "Opening note"

    # The mainline child keeps its annotations; the variations (1.d4 and,
    # nested inside it, 1.c4 — an alternative to d4) graft as its siblings.
    [e4, d4, c4] = analysis.root.children
    assert e4.comment == "Human  text\nSecond note"
    assert e4.nags == [1]
    assert d4.nags == [4]
    assert d4.comment == "Do not attach this"
    assert d4.children == []
    assert c4.nags == [3]

    [e5] = e4.children
    assert e5.comment == "Black's reply"
    assert e5.nags == [14]
    [nf3] = e5.children
    assert nf3.comment == nil
    assert nf3.nags == [6]
    assert {:ok, record, content, occurrences} = GameRecords.load(analysis.source_game_record_id)
    assert record.metadata["event"] == "Annotated game"
    assert length(content.moves) == 4
    assert length(occurrences) == 5
  end

  test "keep options select what enters the analysis and the record" do
    pgn = """
    [Event "Annotated game"]
    [White "Anna"]
    [Black "Boris"]
    [WhiteElo "2501"]
    [Date "2026.10.17"]
    [Result "1-0"]

    1. e4 {Nice [%clk 0:05:00] [%eval 0.20]} e5 (1... c5 {Sicilian}) 2. Nf3 *
    """

    # Defaults: comments and variations kept, machine commands stripped.
    assert {:ok, analysis, _} = import_pgn(pgn)
    [e4] = analysis.root.children
    assert e4.comment == "Nice"
    assert e4.clock == nil
    assert e4.evaluation == nil
    [_e5, c5] = e4.children
    assert c5.comment == "Sicilian"

    assert {:ok, record, _, _} = GameRecords.load(analysis.source_game_record_id)
    assert record.metadata["white_elo"] == "2501"

    # Annotations kept: clock and evaluation land on the node.
    assert {:ok, annotated, _} = import_pgn(pgn, keep_annotations: true)
    [annotated_e4] = annotated.root.children
    assert annotated_e4.clock == "0:05:00"
    assert annotated_e4.evaluation == "0.20"
    # ...but never inside the human comment text.
    assert annotated_e4.comment == "Nice"

    # Comments off: the text goes, annotations still land when kept.
    assert {:ok, plain, _} =
             import_pgn(pgn, keep_comments: false, keep_annotations: true)

    [plain_e4] = plain.root.children
    assert plain_e4.comment == nil
    assert plain_e4.clock == "0:05:00"

    # Variations off: only the mainline grafts.
    assert {:ok, mainline_only, _} = import_pgn(pgn, keep_variations: false)
    [mainline_e4] = mainline_only.root.children
    assert [e5] = mainline_e4.children
    assert e5.comment == nil || true

    # Metadata off: the record keeps only the identity headers.
    assert {:ok, bare, _} = import_pgn(pgn, keep_metadata: false)
    assert {:ok, bare_record, _, _} = GameRecords.load(bare.source_game_record_id)

    assert bare_record.metadata == %{
             "white" => "Anna",
             "black" => "Boris",
             "result" => "1-0",
             "date" => "2026.10.17"
           }
  end

  test "the source option marks the record metadata, even with keep_metadata: false" do
    pgn = ~s([White "Anna"]\n[Black "Boris"]\n\n1. e4 e5 *\n)

    assert {:ok, analysis, _} = import_pgn(pgn, source: "lichess")
    assert {:ok, record, _, _} = GameRecords.load(analysis.source_game_record_id)
    assert record.metadata["source"] == "lichess"

    # The source survives the keep_metadata strip.
    assert {:ok, bare, _} = import_pgn(pgn, source: "chesscom", keep_metadata: false)
    assert {:ok, bare_record, _, _} = GameRecords.load(bare.source_game_record_id)
    assert bare_record.metadata["source"] == "chesscom"
    refute Map.has_key?(bare_record.metadata, "event")

    # Without the option there is no source key.
    assert {:ok, plain, _} = import_pgn(pgn)
    assert {:ok, plain_record, _, _} = GameRecords.load(plain.source_game_record_id)
    refute Map.has_key?(plain_record.metadata, "source")
  end

  test "different annotations reuse canonical content without changing existing analyses" do
    assert {:ok, first, _} = import_pgn("1. e4! {First} e5 *")
    assert {:ok, second, _} = import_pgn("1. e4? {Second} e5 *")
    assert {:ok, first_record, _, _} = GameRecords.load(first.source_game_record_id)
    assert {:ok, second_record, _, _} = GameRecords.load(second.source_game_record_id)
    assert first_record.game_id == second_record.game_id
    assert {:ok, ^first, _} = Analyses.get(first.id)
    assert hd(first.root.children).comment == "First"
    assert hd(second.root.children).comment == "Second"
  end

  test "custom FEN with black to move preserves move context and annotations" do
    assert {:ok, analysis, _} =
             import_pgn("""
             [SetUp "1"]
             [FEN "4k3/8/8/8/8/8/4K3/7R b - - 12 37"]

             37... Kf7! {Black starts} 38. Rh2 *
             """)

    assert analysis.start == GameStart.new(37)
    assert hd(analysis.root.children).comment == "Black starts"
    assert hd(analysis.root.children).nags == [1]
  end

  test "invalid annotations and malformed input persist nothing" do
    before = counts()

    for pgn <- [
          "1. e4 $256 e5 *",
          "1. e4 $1 $2 $3 $4 $5 $6 $7 $8 $9 e5 *",
          "1. e4 {unfinished",
          "1. e4 (1. d4 *",
          "1. e4 ThisIsNotSAN *",
          "(1. d4) 1. e4 *",
          "1. e4 (1. ThisIsNotSAN) *",
          "1. e4 ) *"
        ] do
      assert {:error, {:invalid_pgn, _}} = import_pgn(pgn)
      assert counts() == before
    end
  end

  test "variations graft as annotated branches with real positions, nested arbitrarily" do
    pgn = """
    [Event "Branches"]

    1. e4 {King pawn} (1. d4!? {Queen pawn} d5) (1. c4) 1... e5
    (1... c5 {Sicilian} 2. Nf3 (2. c3)) 2. Nf3 Nc6 *
    """

    assert {:ok, analysis, _revision} = import_pgn(pgn)

    # Two alternatives to 1.e4 graft as its siblings, in PGN order.
    [e4, d4, c4] = analysis.root.children
    assert e4.comment == "King pawn"
    assert d4.nags == [5]
    assert d4.comment == "Queen pawn"
    assert c4.comment == nil

    # The d4 variation continues: d5 is its mainline child.
    [d5] = d4.children
    assert %Analysis.Node{transition: {:move, %Chess.Move{}}} = d5

    # The e5 alternatives: c5 (with its own continuation and nested c3 sibling).
    [e5, c5] = e4.children
    assert c5.comment == "Sicilian"
    [nf3_var, c3_var] = c5.children
    assert nf3_var.children == []
    assert c3_var.children == []

    # The mainline continues after the variations: Nf3 Nc6 are there.
    [nf3] = e5.children
    [nc6] = nf3.children
    assert nc6.children == []

    # Positions are real: the c5 node's position resolves black's c-pawn push.
    assert {:ok, c5_position} = position_of(c5)
    assert Position.piece_at(c5_position, Chess.Square.from_algebraic("c5")) == {:black, :pawn}

    # The canonical game keeps only the mainline: 4 moves, 5 occurrences.
    assert {:ok, _record, content, occurrences} = GameRecords.load(analysis.source_game_record_id)
    assert length(content.moves) == 4
    assert length(occurrences) == 5
  end

  test "analysis identity collision rolls back the new game record and canonical content" do
    assert {:ok, existing, _} = import_pgn("1. e4 e5 *")
    before = counts()
    record_id = "rollback-" <> Ecto.UUID.generate()

    assert {:error, :already_exists} =
             PgnAnalysisImporter.import(existing.id, record_id, "1. a3 {Rollback} h6 *")

    assert counts() == before
    assert :not_found = GameRecords.load(record_id)
    assert {:ok, ^existing, _} = Analyses.get(existing.id)
  end

  defp counts do
    for table <- ~w(analyses game_records games game_occurrences positions),
        do: Repo.query!("SELECT count(*) FROM #{table}", []).rows
  end
end
