defmodule Analysis.PositionEvalsTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionEvals
  alias Analysis.PositionStore
  alias Chess.Position
  alias OpenChessLab.Repo

  setup do
    Repo.query!(
      "TRUNCATE TABLE position_evals, game_records, game_occurrences, games, positions RESTART IDENTITY CASCADE",
      []
    )

    :ok
  end

  test "cache lookups and stores emit telemetry" do
    parent = self()

    for event <- [:cache_lookup, :cache_store] do
      :telemetry.attach(
        "probe-#{event}",
        [:openchesslab, :engine, event],
        fn _event, measurements, metadata, _config ->
          send(parent, {event, measurements.count, Map.get(metadata, :result)})
        end,
        nil
      )
    end

    position_id = PositionStore.append(Position.starting_position())

    assert :not_found = PositionEvals.get(position_id, "stockfish-19-lite-single")
    assert_received {:cache_lookup, 1, :miss}

    :ok =
      PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 20,
        eval_cp: 34,
        mate: nil,
        best_move: "e2e4",
        pv: "e2e4 e7e5 g1f3",
        nodes: 612_345
      })

    assert_received {:cache_store, 1, nil}

    assert {:ok, _eval} = PositionEvals.get(position_id, "stockfish-19-lite-single")
    assert_received {:cache_lookup, 1, :hit}

    for event <- [:cache_lookup, :cache_store] do
      :telemetry.detach("probe-#{event}")
    end
  end

  test "stores and reads back an evaluation per position and engine" do
    position_id = PositionStore.append(Position.starting_position())

    assert :not_found = PositionEvals.get(position_id, "stockfish-19-lite-single")

    :ok =
      PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 20,
        eval_cp: 34,
        mate: nil,
        best_move: "e2e4",
        pv: "e2e4 e7e5 g1f3",
        nodes: 612_345
      })

    assert {:ok, eval} = PositionEvals.get(position_id, "stockfish-19-lite-single")
    assert eval.depth == 20
    assert eval.eval_cp == 34
    assert eval.best_move == "e2e4"
    assert eval.pv == "e2e4 e7e5 g1f3"
    assert eval.nodes == 612_345
    assert eval.multipv == 1
    assert [%{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4 e7e5 g1f3"}] = eval.lines

    # Stored as a jsonb array, not a double-encoded string.
    assert Repo.query!(
             "SELECT jsonb_typeof(lines) FROM position_evals WHERE position_id = $1 AND engine = $2",
             [position_id, "stockfish-19-lite-single"]
           ).rows == [["array"]]

    # Another engine identity is a separate row.
    assert :not_found = PositionEvals.get(position_id, "stockfish-16")

    assert %{} = PositionEvals.get_many([position_id], "stockfish-16")

    assert %{^position_id => %{depth: 20}} =
             PositionEvals.get_many([position_id], "stockfish-19-lite-single")
  end

  test "the deepest evaluation wins; equal depth refreshes" do
    position_id = PositionStore.append(Position.starting_position())

    :ok = PositionEvals.put(position_id, "engine", %{depth: 20, eval_cp: 30})
    :ok = PositionEvals.put(position_id, "engine", %{depth: 12, eval_cp: -90})

    assert {:ok, %{depth: 20, eval_cp: 30}} = PositionEvals.get(position_id, "engine")

    :ok = PositionEvals.put(position_id, "engine", %{depth: 20, eval_cp: 31, best_move: "d2d4"})

    assert {:ok, %{depth: 20, eval_cp: 31, best_move: "d2d4"}} =
             PositionEvals.get(position_id, "engine")
  end

  test "multi-line evaluations round-trip with their multipv coverage" do
    position_id = PositionStore.append(Position.starting_position())

    lines = [
      %{"multipv" => 1, "score_cp" => 30, "pv" => "e2e4 e7e5"},
      %{"multipv" => 2, "score_cp" => 12, "pv" => "d2d4"},
      %{"multipv" => 3, "score_mate" => -2, "pv" => "g1f3"}
    ]

    :ok =
      PositionEvals.put(position_id, "engine", %{
        depth: 18,
        eval_cp: 30,
        best_move: "e2e4",
        pv: "e2e4 e7e5",
        multipv: 3,
        lines: lines
      })

    assert {:ok, eval} = PositionEvals.get(position_id, "engine")
    assert eval.multipv == 3
    assert eval.lines == lines
  end

  test "positions can be removed; their evaluations go with them" do
    position_id = PositionStore.append(Position.starting_position())
    :ok = PositionEvals.put(position_id, "engine", %{depth: 12, eval_cp: 5})

    Repo.query!("DELETE FROM positions WHERE id = $1", [position_id])

    assert :not_found = PositionEvals.get(position_id, "engine")
  end
end
