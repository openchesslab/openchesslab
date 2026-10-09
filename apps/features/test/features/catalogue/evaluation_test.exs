defmodule Features.Catalogue.EvaluationTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position is balanced" do
    features = extract(@start)

    assert features["evaluation.material_advantage"] == 0
    assert features["evaluation.mobility_advantage"] == 0
    assert features["evaluation.space_advantage"] == 0
    assert features["evaluation.king_safety_advantage"] == 0
    assert features["evaluation.initiative_advantage"] == 0
    assert features["evaluation.development_advantage"] == 0
    assert features["evaluation.pawn_structure_advantage"] == 0
    assert features["evaluation.piece_activity_advantage"] == 0
    assert features["evaluation.tactical_advantage"] == 0
    assert features["evaluation.attack_strength"] == 0
    assert features["evaluation.defensive_strength"] == 0
    assert features["evaluation.total_evaluation"] == 0.0
    assert features["evaluation.positional_advantage"] == 0.0
    assert features["evaluation.compensation"] == 0.0

    assert features["evaluation.winning_drawing_losing"] ==
             %{"white" => "drawing", "black" => "drawing"}
  end

  test "an extra knight is a winning evaluation" do
    features = extract("4k3/8/8/8/8/8/4P1N1/4K3 w - - 0 1")

    assert features["evaluation.material_advantage"] == 4
    assert features["evaluation.total_evaluation"] == 5.0

    assert features["evaluation.winning_drawing_losing"] ==
             %{"white" => "winning", "black" => "losing"}
  end
end
