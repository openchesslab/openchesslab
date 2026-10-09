defmodule Features.Catalogue.SpaceTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["space.total"] == 0
    assert features["space.kingside"] == 0
    assert features["space.queenside"] == 0
    assert features["space.center"] == 0
    assert features["space.enemy_half_control"] == %{"white" => 0, "black" => 0}
    assert features["space.cramping"] == %{"white" => false, "black" => false}
    assert features["space.advanced_chain"] == %{"white" => false, "black" => false}
    assert features["space.gaining_push"] == %{"white" => true, "black" => true}
  end

  test "an advanced pawn gains space" do
    features = extract("4k3/8/8/8/4P3/8/8/4K3 w - - 0 1")

    assert features["space.total"] == 2
    assert features["space.enemy_half_control"]["white"] == 2
    assert features["space.kingside"] != 0
  end
end
