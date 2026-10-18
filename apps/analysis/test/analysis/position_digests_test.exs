defmodule Analysis.PositionDigestsTest do
  use ExUnit.Case, async: false

  alias Analysis.FeatureDigest
  alias Analysis.PositionDigests
  alias Analysis.PositionFeatures
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

  test "a stored position gets its honest digest atoms" do
    position_id = PositionStore.append(Position.starting_position())

    assert {:ok, ids} = PositionDigests.store_position_id(position_id)
    assert is_list(ids)

    assert {:ok, fetched} = PositionDigests.fetch(position_id)
    assert Enum.sort(fetched) == Enum.sort(ids)

    # Spot-check a few atoms of the starting position.
    for atom <- [
          "material.signature:w:Q1R2B2N2P8",
          "state.king_squares:w:e1",
          "state.king_squares:b:e8"
        ] do
      assert FeatureDigest.id_of(atom) in fetched
    end
  end

  test "storing twice is an idempotent upsert" do
    position_id = PositionStore.append(Position.starting_position())

    assert {:ok, first} = PositionDigests.store_position_id(position_id)
    assert {:ok, second} = PositionDigests.store_position_id(position_id)
    assert Enum.sort(first) == Enum.sort(second)

    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM position_digests WHERE position_id = $1", [position_id])

    assert count == 1
  end

  test "an unknown position honestly has no digest" do
    assert PositionDigests.fetch(999_999) == :not_found
  end

  test "the feature-vector cache writes the digest in the same extraction" do
    position_id = PositionStore.append(Position.starting_position())

    assert {:ok, _result} = PositionFeatures.fetch_or_extract(position_id)
    assert {:ok, ids} = PositionDigests.fetch(position_id)
    assert ids != []
  end
end
