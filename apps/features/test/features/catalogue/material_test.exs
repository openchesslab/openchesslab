defmodule Features.Catalogue.MaterialTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @rook_endgame "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position counts and values" do
    features = extract(@start)

    for {type, count} <- %{"queen" => 1, "rook" => 2, "bishop" => 2, "knight" => 2, "pawn" => 8} do
      assert features["material.count.#{type}"] == %{"white" => count, "black" => count},
             "wrong count for #{type}"
    end

    assert features["material.total_value"] == %{"white" => 39, "black" => 39}
    assert features["material.difference"] == 0
    assert features["material.value_ratio.per_type"]["pawn"] == 0.5
    assert features["material.value_ratio.per_type"]["queen"] == 0.5

    assert features["material.bishop_pair"] == %{"white" => true, "black" => true}
    assert features["material.bishop_pair.both"]
    refute features["material.imbalance.knight_vs_bishop"]
    refute features["material.imbalance.rook_vs_minor"]
    refute features["material.imbalance.queen_vs_rooks"]
    refute features["material.imbalance.two_rooks_vs_queen"]
    assert features["material.exchange_advantage"] == %{"white" => false, "black" => false}
    refute features["material.imbalanced"]
    refute features["material.bishops.opposite_color"]
    assert features["material.bishops.same_color"]
    refute features["material.queenless"]
    refute features["material.endgame_transition"]
  end

  test "piece counts and imbalance detection" do
    features = extract("2b1k3/8/8/8/8/8/8/4KN2 w - - 0 1")

    assert features["material.count.knight"] == %{"white" => 1, "black" => 0}
    assert features["material.count.bishop"] == %{"white" => 0, "black" => 1}
    assert features["material.imbalance.knight_vs_bishop"]
    refute features["material.imbalance.rook_vs_minor"]
    assert features["material.imbalanced"]
    assert features["material.difference"] == 0
  end

  test "bishop pair flags" do
    features = extract("1b2k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1")

    assert features["material.bishop_pair"] == %{"white" => false, "black" => true}
    refute features["material.bishop_pair.both"]
    assert features["material.count.bishop"] == %{"white" => 1, "black" => 2}
  end

  test "opposite-colored and same-colored bishops" do
    opposite = extract("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1")
    same = extract("1b2k3/8/8/8/8/8/8/2B1K3 w - - 0 1")

    assert opposite["material.bishops.opposite_color"]
    refute opposite["material.bishops.same_color"]

    assert same["material.bishops.same_color"]
    refute same["material.bishops.opposite_color"]
  end

  test "rook versus minor and queen versus rooks imbalances" do
    rook_vs_minor = extract("5n2/8/8/8/8/8/8/3RK3 w - - 0 1")
    queen_vs_rooks = extract("r6r/8/8/8/8/8/8/3QK3 w - - 0 1")
    two_rooks_vs_queen = extract("3qk3/8/8/8/8/8/8/1R2K2R w - - 0 1")

    assert rook_vs_minor["material.imbalance.rook_vs_minor"]
    assert rook_vs_minor["material.exchange_advantage"]["white"]
    refute rook_vs_minor["material.imbalance.knight_vs_bishop"]
    assert queen_vs_rooks["material.imbalance.queen_vs_rooks"]
    assert two_rooks_vs_queen["material.imbalance.two_rooks_vs_queen"]
  end

  test "queenless and endgame transition" do
    queenless = extract(@rook_endgame)

    assert queenless["material.queenless"]
    assert queenless["material.endgame_transition"]
    assert queenless["material.total_value"] == %{"white" => 8, "black" => 8}
    assert queenless["material.difference"] == 0
  end
end
