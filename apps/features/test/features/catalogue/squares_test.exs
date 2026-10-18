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

  test "enemy pieces on your outpost squares are targets, nothing else" do
    # Black knight on d5: defended by the white e-pawn, unreachable for black
    # pawns — a white outpost square with an enemy piece sitting on it.
    features = extract("4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1")

    assert features["squares.enemy_on_outpost"] == %{"white" => ~w(d5), "black" => []}

    # The real-world position from the alignment scan: black knight on e5
    # (white's outpost via the d-pawn) AND a white pawn on d4 (black's
    # outpost via the e5-pawn, past every white pawn's reach).
    features = extract("2k1r3/1pp4p/p7/2p1n3/2PP2p1/PP4P1/5P1P/3R2K1 w - - 0 1")

    assert features["squares.enemy_on_outpost"] == %{"white" => ~w(e5), "black" => ~w(d4)}

    # A friendly piece on the outpost is not an enemy; an undefended enemy
    # piece on the same square is no outpost at all.
    features = extract("4k3/8/8/2N5/1P6/8/8/4K3 w - - 0 1")
    assert features["squares.enemy_on_outpost"]["white"] == []

    features = extract("4k3/8/8/3n4/8/8/8/4K3 w - - 0 1")
    assert features["squares.enemy_on_outpost"]["white"] == []

    # Starting position: no outposts, hence nothing on them.
    assert extract(@start)["squares.enemy_on_outpost"] == %{"white" => [], "black" => []}
  end
end
