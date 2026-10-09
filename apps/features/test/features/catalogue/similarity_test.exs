defmodule Features.Catalogue.SimilarityTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp compare(a, b), do: Features.compare(a, b)

  test "start position is identical to itself and no similarity is flagged" do
    features = compare(@start, @start)

    assert features["similarity.exact_same_position"] == true
    assert features["similarity.same_position_other_side"] == false
    assert features["similarity.color_swapped_position"] == false
    assert features["similarity.mirrored_position"] == false

    assert features["similarity.pawn_edit_distance"] == 0
    assert features["similarity.structural_distance"] == 0
    assert features["similarity.one_pawn_shifted"] == false
    assert features["similarity.bishop_knight_substitution"] == false
    assert features["similarity.two_rooks_queen_substitution"] == false

    Enum.each(
      [
        "same_pawn_structure",
        "comparable_pawn_structure",
        "same_material_distribution",
        "comparable_material_distribution",
        "same_piece_placement_patterns",
        "same_strategic_structure",
        "same_king_safety_structure",
        "same_tactical_geometry",
        "comparable_attack_plan"
      ],
      fn key -> assert features["similarity.#{key}"] == true end
    )
  end

  test "same position with the other side to move" do
    features = compare(@start, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")

    assert features["similarity.same_position_other_side"] == true
    assert features["similarity.exact_same_position"] == false
    assert features["similarity.color_swapped_position"] == true
    assert features["similarity.structural_distance"] == 0
  end

  test "color-swapped position" do
    features = compare("8/8/8/8/8/8/4P3/4K3 w - - 0 1", "4k3/4p3/8/8/8/8/8/8 b - - 0 1")

    assert features["similarity.color_swapped_position"] == true
    assert features["similarity.same_position_other_side"] == false
    assert features["similarity.exact_same_position"] == false
  end

  test "horizontal mirror" do
    features = compare("8/8/8/8/8/8/8/1K6 w - - 0 1", "8/8/8/8/8/8/8/6K1 w - - 0 1")

    assert features["similarity.mirrored_position"] == true
  end

  test "a single shifted pawn" do
    e4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"

    features = compare(@start, e4)

    assert features["similarity.one_pawn_shifted"] == true
    assert features["similarity.pawn_edit_distance"] == 1
    assert features["similarity.structural_distance"] == 1
    assert features["similarity.same_pawn_structure"] == false
    assert features["similarity.comparable_pawn_structure"] == true
    assert features["similarity.exact_same_position"] == false
  end

  test "bishop for knight substitution" do
    features = compare(@start, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RBBQKBNR w KQkq - 0 1")

    assert features["similarity.bishop_knight_substitution"] == true
    assert features["similarity.same_material_distribution"] == false
    assert features["similarity.same_piece_placement_patterns"] == false
  end

  test "two rooks for a queen substitution" do
    features = compare("4k3/8/8/8/8/8/8/RR2K3 w - - 0 1", "4k3/8/8/8/8/8/8/Q3K3 w - - 0 1")

    assert features["similarity.two_rooks_queen_substitution"] == true
    assert features["similarity.exact_same_position"] == false
  end

  test "extract accepts a reference that fills the similarity features" do
    assert Features.extract(@start, reference: @start).features["similarity.exact_same_position"] ==
             true
  end
end
