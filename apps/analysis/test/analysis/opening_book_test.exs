defmodule Analysis.OpeningBookTest do
  use ExUnit.Case, async: false

  alias Analysis.{GameContent, GameRecords, GameStart, GameStore, OpeningBook, PositionStore}
  alias Chess.{Move, Position, Square}
  alias OpenChessLab.Repo

  setup do
    Repo.query!(
      "TRUNCATE TABLE game_records, game_occurrences, games, position_evals, positions RESTART IDENTITY CASCADE",
      []
    )

    :ok
  end

  defp move(from, to), do: Move.new(Square.from_algebraic(from), Square.from_algebraic(to))

  defp create_game(record_id, moves, result) do
    start_id = PositionStore.append(Position.starting_position())

    {:ok, record} =
      GameRecords.create(
        record_id,
        GameContent.new(start_id, moves),
        GameStart.standard(),
        %{"white" => "White", "black" => "Black", "result" => result}
      )

    record
  end

  test "classifies positions by ECO from the vendored dataset" do
    start = Position.starting_position()

    # The starting position itself is unnamed, like on lichess.
    assert :not_found = OpeningBook.classify(start)

    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    {:ok, after_e4_c5} = Position.apply_move(after_e4, move("c7", "c5"))

    assert {:ok, %{eco: "B00", name: "King's Pawn Game"}} = OpeningBook.classify(after_e4)
    assert {:ok, %{eco: "B20", name: name}} = OpeningBook.classify(after_e4_c5)
    assert name =~ "Sicilian"

    # An artificial position has no classification.
    empty = Position.new()
    assert :not_found = OpeningBook.classify(empty)
  end

  test "classifies a line by its deepest named position" do
    record = create_game("eco-line", [move("e2", "e4"), move("e7", "e5")], "1-0")
    {:ok, analysis, _} = Analysis.Analyses.create_from_game_record("eco-line-analysis", record.id)

    # The root is unnamed; at 1.e4 e5 it is a King's Pawn Game (C20).
    assert :not_found = OpeningBook.classify_line(analysis, [])

    assert {:ok, %{eco: "C20", name: "King's Pawn Game"}} =
             OpeningBook.classify_line(analysis, [0, 0])
  end

  test "aggregates corpus moves with per-result counts and opening names" do
    create_game("book-draw", [move("e2", "e4"), move("c7", "c5")], "1/2-1/2")
    create_game("book-win", [move("e2", "e4"), move("e7", "e5")], "1-0")

    start = Position.starting_position()
    start_id = PositionStore.append(start)

    [e4] = OpeningBook.moves(start, start_id)
    assert e4.san == "e4"
    assert e4.games == 2
    assert e4.white == 1
    assert e4.draws == 1
    assert e4.black == 0
    assert %{name: name} = e4.opening
    assert name =~ "King"

    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    after_e4_id = PositionStore.append(after_e4)

    moves = OpeningBook.moves(after_e4, after_e4_id)
    by_san = Map.new(moves, &{&1.san, &1})

    assert by_san["c5"].games == 1
    assert by_san["c5"].draws == 1
    assert %{eco: "B20"} = by_san["c5"].opening
    assert by_san["e5"].games == 1
    assert by_san["e5"].white == 1
  end

  test "new games fill the occurrence move column and the backfill repairs old rows" do
    record = create_game("book-backfill", [move("e2", "e4"), move("e7", "e5")], "1-0")

    [[filled]] =
      Repo.query!(
        "SELECT count(*) FROM game_occurrences WHERE game_id = $1 AND move IS NOT NULL",
        [record.game_id]
      ).rows

    assert filled == 2

    # Simulate a pre-column row and repair it.
    Repo.query!("UPDATE game_occurrences SET move = NULL WHERE game_id = $1", [record.game_id])
    assert {:ok, 2} = GameStore.backfill_occurrence_moves()

    [[again]] =
      Repo.query!(
        "SELECT count(*) FROM game_occurrences WHERE game_id = $1 AND move IS NOT NULL",
        [record.game_id]
      ).rows

    assert again == 2
  end
end
