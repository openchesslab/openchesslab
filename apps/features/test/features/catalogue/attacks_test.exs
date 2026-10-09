defmodule Features.Catalogue.AttacksTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["attacks.map"]["white"] != []
    assert features["attacks.attacked_squares"] != []
    assert features["attacks.attackers_per_square"]["white"] |> map_size() > 0
    assert features["attacks.defenders_per_square"]["white"]["b1"] == 1
    assert features["attacks.f2_f7"] == %{"white" => 0, "black" => 0}
    assert features["attacks.pressure_piece"] == %{"white" => nil, "black" => nil}
  end

  test "loose and attacked pieces" do
    features = extract("4k3/8/8/8/8/5r2/5P2/K7 w - - 0 1")

    assert features["attacks.attacked_pieces"]["black"] == ~w(f2)
    assert "f2" in features["attacks.loose"]["white"]
    assert "f2" in features["attacks.en_prise"]["white"]
    refute "f2" in features["attacks.hanging"]["white"]
    assert features["attacks.f2_f7"]["white"] == 1
  end

  test "hanging piece under two attackers" do
    features = extract("4k3/8/4r1b1/8/4N3/8/8/4K3 w - - 0 1")

    assert "e4" in features["attacks.hanging"]["white"]
    assert features["attacks.attackers_per_square"]["black"]["e4"] == 2
  end
end
