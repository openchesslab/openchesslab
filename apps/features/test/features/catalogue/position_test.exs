defmodule Features.Catalogue.PositionTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position is closed, quiet and symmetric" do
    features = extract(@start)

    assert features["position.symmetric_position"] == true
    assert features["position.asymmetric_position"] == false
    assert features["position.closed_position"] == true
    assert features["position.semi_open_position"] == false
    assert features["position.open_position"] == false
    assert features["position.locked_position"] == false
    assert features["position.quiet_position"] == true
    assert features["position.tactical_position"] == false
    assert features["position.sharp_position"] == false
    assert features["position.maneuvering_position"] == true
    assert features["position.endgame_like_position"] == false
    assert features["position.queenless_middlegame"] == false
    assert features["position.material_imbalanced_position"] == false
    assert features["position.opposite_side_castling_position"] == false
  end

  test "opposite-side castling" do
    features = extract("6k1/8/8/8/8/8/8/2K5 w - - 0 1")

    assert features["position.opposite_side_castling_position"] == true
    assert features["position.symmetric_position"] == false
    assert features["position.asymmetric_position"] == true
  end

  test "queenless endgame" do
    features = extract("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")

    assert features["position.endgame_like_position"] == true
    assert features["position.queenless_middlegame"] == false
  end

  test "open position without pawns" do
    features = extract("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")

    assert features["position.open_position"] == true
    assert features["position.semi_open_position"] == false
    assert features["position.closed_position"] == false
  end

  test "semi-open position" do
    features = extract("r1bq1rk1/ppp1p1pp/2np1n2/6NQ/2B1P3/2N5/PP6/R1B2RK1 b - - 0 1")

    assert features["position.semi_open_position"] == true
    assert features["position.open_position"] == false
    assert features["position.closed_position"] == false
  end

  test "material imbalance" do
    features = extract("4k3/8/8/8/8/8/4P1N1/4K3 w - - 0 1")
    assert features["position.material_imbalanced_position"] == true
  end
end
