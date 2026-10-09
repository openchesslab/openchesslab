defmodule Features.Catalogue.InitiativeTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["initiative.initiative"] == %{"white" => false, "black" => false}
    assert features["initiative.tempo_advantage"] == %{"white" => true, "black" => false}
    assert features["initiative.attacking_momentum"] == %{"white" => false, "black" => false}
    assert features["initiative.ability_to_create_threats"] == %{"white" => 0, "black" => 0}
    assert features["initiative.attacking_potential"] == %{"white" => 0, "black" => 0}
    assert features["initiative.defending_burden"] == %{"white" => 0, "black" => 0}
    assert features["initiative.development_lead"] == %{"white" => 0, "black" => 0}
    assert features["initiative.forcing_move_density"] == %{"white" => 0.0, "black" => 0.0}
    assert features["initiative.tactical_potential"] == %{"white" => 0, "black" => 0}
    assert features["initiative.dynamic_compensation"] == %{"white" => false, "black" => false}

    assert features["initiative.positional_compensation"] ==
             %{"white" => false, "black" => false}

    assert features["initiative.sacrifice_compensation"] ==
             %{"white" => false, "black" => false}
  end

  test "attacking build-up gives momentum and initiative" do
    features = extract("r1bq1rk1/ppp1p1pp/2np1n2/6NQ/2B1P3/2N5/PP6/R1B2RK1 b - - 0 1")

    assert features["initiative.attacking_momentum"] == %{"white" => true, "black" => false}
    assert features["initiative.initiative"] == %{"white" => true, "black" => false}
  end

  test "material lag with attacking counterplay is dynamic compensation" do
    features = extract("4k3/8/8/8/3n4/5R2/5P2/4K3 w - - 0 1")

    assert features["initiative.dynamic_compensation"] == %{"white" => false, "black" => true}

    assert features["initiative.sacrifice_compensation"] ==
             %{"white" => false, "black" => true}
  end
end
