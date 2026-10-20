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

  test "picker_atoms enumerates the searchable vocabulary of a feature map" do
    features = %{
      # Booleans count as true even when false.
      "king.opposite_side_castling" => false,
      # Per-side booleans yield both sides.
      "material.bishop_pair" => %{"white" => false, "black" => true},
      # Curated list features yield their presence atom, even when empty.
      "tactics.pin" => %{"white" => [], "black" => ["d4"]},
      "pawns.iqp" => %{"white" => ["d4"], "black" => []},
      # Uncurated lists, numerics and square scalars never enter a picker.
      "some.uncurated_list" => ["a1"],
      "material.total_value" => %{"white" => 39, "black" => 39},
      "state.king_squares" => %{"white" => "e1", "black" => "e8"},
      # The hard exclusions apply here too.
      "pawns.structure" => %{"white" => [], "black" => []},
      "similarity.jaccard" => 0.5,
      "state.side_to_move" => "white",
      "tactics.zwischenzug_possibilities" => %{"white" => [], "black" => []}
    }

    picker = FeatureDigest.picker_atoms(features)

    assert "king.opposite_side_castling" in picker
    assert "material.bishop_pair:w" in picker
    assert "material.bishop_pair:b" in picker
    assert "tactics.pin:w" in picker
    assert "tactics.pin:b" in picker
    assert "pawns.iqp:w" in picker
    assert "pawns.iqp:b" in picker

    refute "some.uncurated_list" in picker
    refute "material.total_value:w" in picker
    refute "state.king_squares:w" in picker
    refute "pawns.structure" in picker
    refute Enum.any?(picker, &String.starts_with?(&1, "similarity."))
    refute "state.side_to_move" in picker
    refute Enum.any?(picker, &String.starts_with?(&1, "tactics.zwischenzug_possibilities"))
  end

  test "every non-square digest atom is in the picker vocabulary" do
    for fen <- [
          "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
          "r1bq1rk1/pp1pppbn/2n2np1/4p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 7",
          "8/5pk1/6p1/3P4/8/2K5/8/4R3 w - - 0 1"
        ] do
      result = Features.extract(fen)
      picker = FeatureDigest.picker_atoms(result.features)

      for atom <- FeatureDigest.atoms(result.features) do
        cond do
          # Composition-specific signatures stay out of the picker.
          String.starts_with?(atom, "material.signature:") ->
            :ok

          # Presence atoms and plain booleans must be listed.
          atom == atom |> String.split(":") |> Enum.take(2) |> Enum.join(":") or
              not String.contains?(atom, ":") ->
            assert atom in picker,
                   "digest atom #{atom} missing from the picker vocabulary"

          # Square-suffixed atoms of curated lists are represented by their
          # presence atom; square-valued scalars have no presence atom.
          true ->
            :ok
        end
      end
    end
  end

  test "search_picker_groups groups the vocabulary by catalogue section" do
    groups = PositionFeatures.search_picker_groups()

    assert is_list(groups)

    assert Enum.all?(groups, fn {section, atoms} ->
             is_integer(section) and section > 0 and atoms == Enum.sort(atoms) and
               atoms == Enum.uniq(atoms)
           end)

    assert groups == PositionFeatures.search_picker_groups()

    all_atoms = List.flatten(for {_section, atoms} <- groups, do: atoms)

    assert "material.bishop_pair:w" in all_atoms
    assert "king.opposite_side_castling" in all_atoms
    assert "tactics.pin:w" in all_atoms
    refute Enum.any?(all_atoms, &String.starts_with?(&1, "material.signature:"))

    # Grouped by the catalogue's own section numbers.
    bishop_pair_section =
      Enum.find_value(groups, fn {section, atoms} ->
        if "material.bishop_pair:w" in atoms, do: section
      end)

    assert bishop_pair_section == Features.Catalogue.fetch!("material.bishop_pair").section
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
