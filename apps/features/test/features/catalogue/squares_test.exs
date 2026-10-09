defmodule Features.Catalogue.SquaresTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["squares.weak"] == %{"white" => [], "black" => []}
    assert features["squares.outpost"] == %{"white" => [], "black" => []}
    assert features["squares.occupied_outpost"] == %{"white" => [], "black" => []}
    assert features["squares.weak_color_complex"] == %{"white" => nil, "black" => nil}
    refute features["squares.dark_weakness"]["white"]
    refute features["squares.light_weakness"]["white"]
    assert features["squares.invasion"] == %{"white" => [], "black" => []}
    assert features["squares.heavy_entry"] == %{"white" => [], "black" => []}
  end

  test "weak squares, holes and outposts" do
    features = extract("4k3/8/8/3p4/8/8/8/4K3 w - - 0 1")

    assert features["squares.weak"]["white"] == ~w(c4 e4)
    refute features["squares.dark_weakness"]["white"]

    features = extract("4k3/8/8/2N5/1P6/8/8/4K3 w - - 0 1")
    assert features["squares.outpost"]["white"] == ~w(a5)
    assert features["squares.occupied_outpost"]["white"] == ~w(c5)

    potential = features["squares.potential_outpost"]["white"]
    assert "a5" in potential
    refute "c5" in potential
  end
end
