defmodule Analysis.DigestBackfillTest do
  use ExUnit.Case, async: false

  alias Analysis.DigestBackfill
  alias Analysis.FeatureDigest
  alias Analysis.PositionDigests
  alias Analysis.PositionStore
  alias Chess.Position
  alias OpenChessLab.Repo

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        position_features,
        positions,
        feature_atoms
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    FeatureDigest.reload_cache()
    :ok
  end

  test "run fills missing digests and is then a no-op" do
    position_id = PositionStore.append(Position.starting_position())

    stats = DigestBackfill.run(chunk_size: 2, workers: 2)

    assert stats.computed == 1
    assert stats.failed == 0
    assert {:ok, _ids} = PositionDigests.fetch(position_id)

    assert DigestBackfill.run(chunk_size: 2, workers: 2) == %{computed: 0, failed: 0}
  end

  test "run honors the limit" do
    alias Chess.Move
    alias Chess.Square

    first = PositionStore.append(Position.starting_position())

    {:ok, second_position} =
      Position.apply_move(
        Position.starting_position(),
        Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      )

    second = PositionStore.append(second_position)

    stats = DigestBackfill.run(limit: 1, chunk_size: 100, workers: 2)

    assert stats.computed + stats.failed == 1

    remaining =
      [first, second]
      |> Enum.count(fn id -> PositionDigests.fetch(id) == :not_found end)

    assert remaining == 1

    # A follow-up run finishes the job.
    assert DigestBackfill.run(workers: 2) == %{computed: 1, failed: 0}
    assert remaining_done?([first, second])
  end

  defp remaining_done?(ids) do
    Enum.all?(ids, fn id ->
      match?({:ok, _}, PositionDigests.fetch(id))
    end)
  end
end
