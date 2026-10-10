defmodule Analysis.PositionFeaturesTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.PositionFeatures
  alias Analysis.PositionStore
  alias Chess.Position
  alias Features.Chess.FEN
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        position_feature_vectors,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "extracts the full feature catalogue for a chess position" do
    assert {:ok, result} = PositionFeatures.extract(Position.starting_position())

    assert result.version == "0.1.0"
    assert map_size(result.features) == 371
    assert result.features == Features.extract(FEN.start_fen()).features
  end

  test "extracts features for a stored position id" do
    position_id = PositionStore.append(Position.starting_position())

    assert {:ok, result} = PositionFeatures.extract_position_id(position_id)
    assert result.features["material.difference"] == 0

    assert PositionFeatures.fetch(position_id) == :not_found
  end

  test "extracts features for an analysis node" do
    analysis_id = "features-#{System.unique_integer([:positive])}"

    assert {:ok, _analysis, 1} = Analyses.create(analysis_id)
    assert {:ok, result} = PositionFeatures.extract_at(analysis_id, [])
    assert map_size(result.features) == 371

    assert {:error, :analysis_not_found} = PositionFeatures.extract_at("missing", [])
  end

  test "stores the feature vector per position and fetches it back" do
    position = Position.starting_position()

    assert {:ok, result} = PositionFeatures.store(position)

    assert {:ok, position_id} = PositionStore.find(position)

    assert {:ok, fetched} = PositionFeatures.fetch(position_id)
    assert fetched.version == result.version
    assert fetched.fen == result.fen
    assert fetched.features == Jason.decode!(Jason.encode!(result.features))
  end

  test "fetch_or_extract computes and stores on first access" do
    position_id = PositionStore.append(Position.starting_position())

    assert PositionFeatures.fetch(position_id) == :not_found

    assert {:ok, result} = PositionFeatures.fetch_or_extract(position_id)

    assert {:ok, fetched} = PositionFeatures.fetch(position_id)
    assert fetched.features == Jason.decode!(Jason.encode!(result.features))

    assert {:ok, fetched_again} = PositionFeatures.fetch_or_extract(position_id)
    assert fetched_again.features == fetched.features
  end

  test "backfills feature vectors only for positions without one" do
    position_id = PositionStore.append(Position.starting_position())

    assert {:ok, %{computed: 1, cached: 0, failed: 0}} = PositionFeatures.backfill()
    assert {:ok, %{computed: 0, cached: 1, failed: 0}} = PositionFeatures.backfill()

    assert {:ok, _result} = PositionFeatures.fetch(position_id)
  end
end
