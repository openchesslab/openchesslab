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
    assert features["similarity.comparable_attack_plan"] == false
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
        "same_tactical_geometry"
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

  test "a two-rank pawn advance takes two elementary edits" do
    e4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"

    features = compare(@start, e4)

    assert features["similarity.one_pawn_shifted"] == true
    assert features["similarity.pawn_edit_distance"] == 2
    assert features["similarity.structural_distance"] == 2
    assert features["similarity.same_pawn_structure"] == false
    assert features["similarity.comparable_pawn_structure"] == true
    assert features["similarity.exact_same_position"] == false
  end

  test "one-rank pawn displacement costs one edit" do
    before = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
    after_shift = "4k3/8/8/8/8/4P3/8/4K3 w - - 0 1"

    result = compare(before, after_shift)
    assert result["similarity.pawn_edit_distance"] == 1
    assert result["similarity.structural_distance"] == 1
    assert result["similarity.comparable_pawn_structure"]
  end

  test "three pawn shifts on the same file cost three edits, not one changed file" do
    before = "4k3/8/P7/8/P7/8/P7/4K3 w - - 0 1"
    after_shift = "4k3/P7/8/P7/8/P7/8/4K3 w - - 0 1"

    result = compare(before, after_shift)
    reverse = compare(after_shift, before)

    assert result["similarity.pawn_edit_distance"] == 3
    assert reverse["similarity.pawn_edit_distance"] == 3
    assert result["similarity.structural_distance"] == 3
    refute result["similarity.comparable_pawn_structure"]
  end

  test "one-rank diagonal relocation counts as one edit" do
    before = "4k3/8/8/8/4P3/8/8/4K3 w - - 0 1"
    after_shift = "4k3/8/8/3P4/8/8/8/4K3 w - - 0 1"

    assert compare(before, after_shift)["similarity.pawn_edit_distance"] == 1
    assert compare(after_shift, before)["similarity.pawn_edit_distance"] == 1
  end

  test "simultaneous white and black edits on one file count separately" do
    before = "4k3/p7/8/8/8/8/P7/4K3 w - - 0 1"
    after_shift = "4k3/8/p7/8/8/P7/8/4K3 w - - 0 1"

    assert compare(before, after_shift)["similarity.pawn_edit_distance"] == 2
    assert compare(after_shift, before)["similarity.pawn_edit_distance"] == 2
  end

  test "removal and insertion are symmetric and never change pawn color for free" do
    white = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    black = "4k3/8/8/8/8/8/p7/4K3 w - - 0 1"
    empty = "4k3/8/8/8/8/8/8/4K3 w - - 0 1"

    assert compare(white, empty)["similarity.pawn_edit_distance"] == 1
    assert compare(empty, white)["similarity.pawn_edit_distance"] == 1
    assert compare(white, black)["similarity.pawn_edit_distance"] == 2
  end

  test "a remote displacement takes two edits, not one local shift" do
    before = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    after_shift = "4k3/7P/8/8/8/8/8/4K3 w - - 0 1"

    result = compare(before, after_shift)
    assert result["similarity.pawn_edit_distance"] == 2
    refute result["similarity.one_pawn_shifted"]
  end

  test "an actual kingside attack is comparable to itself but not to no attack" do
    attacking = "r1bq1rk1/ppp1p1pp/2np1n2/6NQ/2B1P3/2N5/PP6/R1B2RK1 b - - 0 1"

    attack_features = Features.extract(attacking, sections: [15]).features
    assert attack_features["goals.kingside_attack"]["white"]

    assert compare(attacking, attacking)["similarity.comparable_attack_plan"]
    refute compare(@start, attacking)["similarity.comparable_attack_plan"]
    refute compare(attacking, @start)["similarity.comparable_attack_plan"]
  end

  test "two positions can share an active attack motif even if other motifs differ" do
    board = Features.Chess.Board.startpos()
    white_kingside = %{"white" => true, "black" => false}

    first =
      with_attack_signals(board, %{
        "goals.kingside_attack" => white_kingside
      })

    second =
      with_attack_signals(board, %{
        "goals.kingside_attack" => white_kingside,
        "goals.central_attack" => %{"white" => true, "black" => false}
      })

    assert compare(first, second)["similarity.comparable_attack_plan"]
    assert compare(second, first)["similarity.comparable_attack_plan"]
  end

  test "opposite colors or different active motifs are not comparable attack plans" do
    board = Features.Chess.Board.startpos()

    white_kingside =
      with_attack_signals(board, %{
        "goals.kingside_attack" => %{"white" => true, "black" => false}
      })

    black_kingside =
      with_attack_signals(board, %{
        "goals.kingside_attack" => %{"white" => false, "black" => true}
      })

    white_queenside =
      with_attack_signals(board, %{
        "goals.queenside_attack" => %{"white" => true, "black" => false}
      })

    refute compare(white_kingside, black_kingside)["similarity.comparable_attack_plan"]
    refute compare(white_kingside, white_queenside)["similarity.comparable_attack_plan"]
  end

  # Controlled, precomputed indicator maps isolate comparison semantics from
  # the independent heuristic detectors tested in GoalsTest.
  defp with_attack_signals(board, overrides) do
    digests = Features.Catalogue.Similarity.digests(board)
    %{board | similarity_cache: %{digests | attack: Map.merge(digests.attack, overrides)}}
  end

  test "same strategic structure permits a rook to move along the same open file" do
    rook_on_c1 = "4k3/p7/8/8/8/8/P7/2R1K3 w - - 0 1"
    rook_on_c3 = "4k3/p7/8/8/8/2R5/P7/4K3 w - - 0 1"

    result = compare(rook_on_c1, rook_on_c3)

    assert result["similarity.same_pawn_structure"]
    assert result["similarity.same_strategic_structure"]
    assert compare(rook_on_c3, rook_on_c1)["similarity.same_strategic_structure"]
    refute result["similarity.same_piece_placement_patterns"]
  end

  test "same strategic structure distinguishes rook access to an open file" do
    rook_on_open_file = "4k3/p7/8/8/8/8/P7/2R1K3 w - - 0 1"
    rook_behind_pawn = "4k3/p7/8/8/8/8/P7/R3K3 w - - 0 1"

    result = compare(rook_on_open_file, rook_behind_pawn)

    assert result["similarity.same_pawn_structure"]
    refute result["similarity.same_strategic_structure"]
  end

  test "same strategic structure distinguishes pawn shape and king placement" do
    original = "4k3/p7/8/8/8/8/P7/2R1K3 w - - 0 1"
    different_pawns = "4k3/p7/8/8/8/8/1P6/2R1K3 w - - 0 1"
    different_king = "4k3/p7/8/8/8/8/P7/2R2K2 w - - 0 1"

    refute compare(original, different_pawns)["similarity.same_strategic_structure"]
    refute compare(original, different_king)["similarity.same_strategic_structure"]
  end

  test "tactical geometry recognizes absolute pins on different files" do
    e_file_pin = "4r2k/8/8/8/4N3/8/8/4K3 b - - 0 1"
    c_file_pin = "2r4k/8/8/8/2N5/8/8/2K5 b - - 0 1"

    assert Features.extract(e_file_pin, sections: [12]).features["tactics.absolute_pin"]["white"] ==
             ["e4"]

    assert Features.extract(c_file_pin, sections: [12]).features["tactics.absolute_pin"]["white"] ==
             ["c4"]

    assert compare(e_file_pin, c_file_pin)["similarity.same_tactical_geometry"]
    assert compare(c_file_pin, e_file_pin)["similarity.same_tactical_geometry"]
    refute compare(e_file_pin, c_file_pin)["similarity.exact_same_position"]
  end

  test "tactical geometry distinguishes a pin from a fork" do
    pinned_knight = "4r2k/8/8/8/4N3/8/8/4K3 b - - 0 1"
    forked_rooks = "7k/8/8/8/8/8/3n4/1R2KR2 b - - 0 1"

    assert Features.extract(forked_rooks, sections: [12]).features["tactics.fork"]["black"] ==
             ["d2"]

    refute compare(pinned_knight, forked_rooks)["similarity.same_tactical_geometry"]
  end

  test "tactical geometry preserves the side and count of tactical motifs" do
    white_pinned = "4r2k/8/8/8/4N3/8/8/4K3 b - - 0 1"
    black_pinned = "4k3/8/8/4n3/8/8/8/K3R3 w - - 0 1"

    one_pin = "7k/8/8/8/1b6/2N5/3K4/8 b - - 0 1"
    two_pins = "7k/8/8/8/1b3b2/2N1N3/3K4/8 b - - 0 1"

    assert Features.extract(black_pinned, sections: [12]).features["tactics.absolute_pin"][
             "black"
           ] ==
             ["e5"]

    assert Features.extract(two_pins, sections: [12]).features["tactics.absolute_pin"]["white"] ==
             ~w(c3 e3)

    refute compare(white_pinned, black_pinned)["similarity.same_tactical_geometry"]
    refute compare(one_pin, two_pins)["similarity.same_tactical_geometry"]
  end

  test "matching absence of tactical motifs does not imply the same geometry" do
    kings_only = "4k3/8/8/8/8/8/8/4K3 w - - 0 1"

    refute compare(@start, kings_only)["similarity.same_tactical_geometry"]
    assert compare(kings_only, kings_only)["similarity.same_tactical_geometry"]
  end

  test "the same pieces have the same geometry regardless of who moves" do
    black_to_move = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"

    assert compare(@start, black_to_move)["similarity.same_tactical_geometry"]
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
