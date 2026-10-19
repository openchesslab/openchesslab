defmodule Analysis.FeatureDigestTest do
  use ExUnit.Case, async: false

  alias Analysis.FeatureDigest
  alias Analysis.PositionFeatures
  alias Chess.Position
  alias OpenChessLab.Repo

  setup do
    Repo.query!("TRUNCATE TABLE feature_atoms RESTART IDENTITY")
    FeatureDigest.reload_cache()
    :ok
  end

  test "the start position digests to honest intrinsic atoms" do
    {:ok, result} = PositionFeatures.extract(Position.starting_position())
    atoms = FeatureDigest.atoms(result.features)

    assert "material.signature:w:Q1R2B2N2P8" in atoms
    assert "material.signature:b:Q1R2B2N2P8" in atoms
    assert "state.king_squares:w:e1" in atoms
    assert "state.king_squares:b:e8" in atoms

    # Symmetry facts are intrinsic booleans; tactics and similarity stay out.
    assert "position.symmetric_position" in atoms
    refute "tactics.pin:w" in atoms
    refute Enum.any?(atoms, &String.starts_with?(&1, "similarity."))
    refute Enum.any?(atoms, &String.starts_with?(&1, "evaluation."))

    # The measured near-vacuous feature is pruned, never emitted.
    refute Enum.any?(atoms, &String.starts_with?(&1, "tactics.zwischenzug_possibilities"))
  end

  test "ids are stable: registering twice yields the same ids without growth" do
    first = FeatureDigest.ids_for(["test.atom.alpha", "test.atom.beta"])
    assert length(first) == 2
    assert Enum.all?(first, &is_integer/1)

    %{rows: [[count_after_register]]} = Repo.query!("SELECT count(*) FROM feature_atoms")

    second = FeatureDigest.ids_for(["test.atom.beta", "test.atom.alpha", "test.atom.beta"])
    assert Enum.sort(second) == Enum.sort(first)

    %{rows: [[count_after_reregister]]} = Repo.query!("SELECT count(*) FROM feature_atoms")
    assert count_after_reregister == count_after_register
  end

  test "an atom unknown to the dictionary is honestly unknown" do
    assert FeatureDigest.id_of("test.atom.never-registered") == :unknown

    [id] = FeatureDigest.ids_for(["test.atom.gamma"])
    assert FeatureDigest.id_of("test.atom.gamma") == id
  end

  test "labels expose the dictionary for the future picker" do
    [id] = FeatureDigest.ids_for(["test.atom.label"])
    assert FeatureDigest.labels()[id] == "test.atom.label"
  end

  test "material substitution variants cover both directions and the base" do
    {:ok, result} = PositionFeatures.extract(Position.starting_position())
    features = result.features

    assert FeatureDigest.material_signature(features, "white") ==
             "material.signature:w:Q1R2B2N2P8"

    assert FeatureDigest.material_signature_variants(features, "white", :two_rooks_queen) ==
             [
               "material.signature:w:Q1R2B2N2P8",
               "material.signature:w:Q0R4B2N2P8",
               "material.signature:w:Q2R0B2N2P8"
             ]

    assert FeatureDigest.material_signature_variants(features, "white", :bishop_knight) ==
             [
               "material.signature:w:Q1R2B2N2P8",
               "material.signature:w:Q1R2B1N3P8",
               "material.signature:w:Q1R2B3N1P8"
             ]
  end

  test "substitution variants skip directions that would go negative" do
    {:ok, %{position: bare}} =
      Chess.Notation.FEN.parse("8/8/8/8/8/8/P7/K6k w - - 0 1")

    {:ok, result} = PositionFeatures.extract(bare)

    assert FeatureDigest.material_signature_variants(result.features, "white", :two_rooks_queen) ==
             ["material.signature:w:Q0R0B0N0P1"]
  end
end
