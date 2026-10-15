defmodule Analysis.PgnAnalysisImporterTest do
  use ExUnit.Case, async: false

  alias Analysis.{Analyses, AnalysisStore, GameRecords, GameStart, PgnAnalysisImporter}
  alias OpenChessLab.Repo

  defp import_pgn(pgn) do
    suffix = Ecto.UUID.generate()
    PgnAnalysisImporter.import("pgn-analysis-" <> suffix, "pgn-record-" <> suffix, pgn)
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
    [e4] = analysis.root.children
    assert e4.comment == "Human  text\nSecond note"
    assert e4.nags == [1]
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
          "1. e4 ThisIsNotSAN *"
        ] do
      assert {:error, {:invalid_pgn, _}} = import_pgn(pgn)
      assert counts() == before
    end
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
