defmodule Features.Catalogue.GoalsTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["goals.kingside_attack"] == %{"white" => false, "black" => false}
    assert features["goals.queenside_attack"] == %{"white" => false, "black" => false}
    assert features["goals.minority_attack"] == %{"white" => false, "black" => false}
    assert features["goals.pawn_storm"] == %{"white" => false, "black" => false}
    assert features["goals.trade_queens"] == %{"white" => false, "black" => false}
    assert features["goals.avoid_queen_trade"] == %{"white" => false, "black" => false}
    assert features["goals.central_attack"] == %{"white" => false, "black" => false}
    assert features["goals.double_rooks_on_file"] == %{"white" => false, "black" => false}
    assert features["goals.exchange_bad_piece"] == %{"white" => false, "black" => false}
    assert features["goals.preserve_good_piece"] == %{"white" => false, "black" => false}
    assert features["goals.activate_king"] == %{"white" => false, "black" => false}

    assert features["goals.exploit_color_complex_weakness"] ==
             %{"white" => false, "black" => false}

    assert features["goals.transfer_pieces_to_kingside"] == %{"white" => false, "black" => false}

    assert features["goals.transfer_pieces_to_queenside"] == %{"white" => false, "black" => false}

    assert features["goals.pressure_along_file"] == %{
             "white" => ~w(a1 d1 h1),
             "black" => ~w(a8 d8 h8)
           }

    assert features["goals.pressure_along_diagonal"] == %{"white" => [], "black" => []}
    assert features["goals.occupy_open_file"] == %{"white" => [], "black" => []}
    assert features["goals.pawn_break"] == %{"white" => [], "black" => []}
    assert features["goals.queenside_expansion"] == %{"white" => [], "black" => []}
    assert features["goals.space_gaining_pawn_advance"] == %{"white" => [], "black" => []}
    assert features["goals.rook_lift"] == %{"white" => [], "black" => []}
    assert features["goals.penetrate_seventh_rank"] == %{"white" => [], "black" => []}
    assert features["goals.create_passed_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.advance_passed_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.blockade_passed_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.blockade_isolated_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.attack_isolated_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.attack_backward_pawn"] == %{"white" => [], "black" => []}
    assert features["goals.establish_outpost"] == %{"white" => [], "black" => []}
    assert features["goals.exploit_weak_square"] == %{"white" => [], "black" => []}

    assert features["goals.improve_worst_placed_piece"] == %{
             "white" => ~w(a1 b1 c1 d1 f1 g1 h1 a2 b2 c2 d2 e2 f2 g2 h2),
             "black" => ~w(a7 b7 c7 d7 e7 f7 g7 h7 a8 b8 c8 d8 f8 g8 h8)
           }
  end

  test "kingside attack with three attackers on the king zone" do
    features = extract("r1bq1rk1/ppp1p1pp/2np1n2/6NQ/2B1P3/2N5/PP6/R1B2RK1 b - - 0 1")

    assert features["goals.kingside_attack"] == %{"white" => true, "black" => false}
    assert features["goals.queenside_attack"] == %{"white" => false, "black" => false}
    assert features["goals.occupy_open_file"] == %{"white" => ~w(f1), "black" => ~w(f8)}
  end

  test "opposite-side castling" do
    features = extract("6k1/8/8/8/8/8/8/2K5 w - - 0 1")
    assert features["goals.activate_king"] == %{"white" => true, "black" => true}
  end

  test "endgame activates kings" do
    features = extract("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
    assert features["goals.activate_king"] == %{"white" => true, "black" => true}
  end

  test "passed pawn: advance for the owner, blockade for the defender" do
    features = extract("4k3/8/8/4P3/8/8/8/4K3 w - - 0 1")

    assert features["goals.advance_passed_pawn"] == %{"white" => ~w(e5), "black" => []}
    assert features["goals.blockade_passed_pawn"] == %{"white" => [], "black" => ~w(e5)}
  end

  test "isolated pawn: attack it and blockade its advance" do
    features = extract("4k3/8/8/8/8/8/5p2/4K3 w - - 0 1")

    assert features["goals.attack_isolated_pawn"] == %{"white" => ~w(f2), "black" => []}
    assert features["goals.blockade_isolated_pawn"] == %{"white" => ~w(f3), "black" => []}
    assert features["goals.blockade_passed_pawn"] == %{"white" => ~w(f2), "black" => []}
  end
end
