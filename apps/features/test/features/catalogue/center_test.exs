defmodule Features.Catalogue.CenterTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["center.occupation"] == %{"white" => [], "black" => []}
    assert features["center.control"] == %{"white" => 4, "black" => 4}
    assert features["center.key_control"] == %{"white" => 0, "black" => 0}
    assert features["center.extended"] == %{"white" => 0, "black" => 0}
    assert features["center.pawn_center"] == %{"white" => [], "black" => []}
    assert features["center.piece_center"] == %{"white" => [], "black" => []}
    assert features["center.stable"] == %{"white" => false, "black" => false}
    assert features["center.mobile"] == %{"white" => false, "black" => false}
    refute features["center.locked"]
    assert features["center.open"]
    refute features["center.tension"]
    assert features["center.breakthrough"] == %{"white" => false, "black" => false}
    assert features["center.dominance"] == 0
  end

  test "white pawn centre" do
    features = extract("4k3/8/8/2PP4/8/8/8/4K3 w - - 0 1")

    assert features["center.extended"]["white"] == 2
    assert features["center.pawn_center"]["white"] == ~w(d5)
    refute features["center.open"]
    assert features["center.stable"]["white"]
    assert features["center.mobile"]["white"]
  end
end
