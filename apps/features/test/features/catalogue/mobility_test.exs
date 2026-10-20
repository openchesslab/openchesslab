defmodule Features.Catalogue.MobilityTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "coordinated mirrors uncoordinated and the count" do
    features = extract(@start)

    coordinated = features["mobility.coordinated"]
    uncoordinated = features["mobility.uncoordinated"]
    count = features["mobility.coordination"]

    # The two lists partition the active pieces; the count matches the list.
    for side <- ["white", "black"] do
      assert length(coordinated[side]) == count[side]
      assert coordinated[side] -- uncoordinated[side] == coordinated[side]
      assert uncoordinated[side] -- coordinated[side] == uncoordinated[side]
    end

    # Startpos facts: the rooks are the only undefended pieces (the king is
    # not an "active piece" here), and the queen is defended by her king.
    assert uncoordinated["white"] == ["a1", "h1"]
    assert uncoordinated["black"] == ["a8", "h8"]
    assert "f1" in coordinated["white"]
    assert "d1" in coordinated["white"]
  end

  test "start position" do
    features = extract(@start)

    assert features["mobility.total"] == 40
    assert features["mobility.per_side"] == %{"white" => 20, "black" => 20}
    assert features["mobility.legal_moves"] == 20
    assert features["mobility.development"] == %{"white" => 0, "black" => 0}
    assert features["mobility.development_advantage"] == 0

    assert features["mobility.undeveloped"] == %{
             "white" => ~w(b1 c1 f1 g1),
             "black" => ~w(b8 c8 f8 g8)
           }

    assert features["mobility.development_deficit"] == %{"white" => 5, "black" => 5}

    assert features["mobility.active_passive"] == %{
             "white" => %{"active" => 0, "passive" => 5},
             "black" => %{"active" => 0, "passive" => 5}
           }
  end

  test "development after moving a minor piece" do
    features = extract("rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1")

    assert features["mobility.development"]["white"] == 1
    assert features["mobility.undeveloped"]["white"] == ~w(b1 c1 f1)
    assert features["mobility.development_advantage"] == 1
  end
end
