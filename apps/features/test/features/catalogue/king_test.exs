defmodule Features.Catalogue.KingTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["king.castled"] == %{"white" => false, "black" => false}
    assert features["king.uncastled"] == %{"white" => true, "black" => true}
    assert features["king.center"] == %{"white" => false, "black" => false}
    assert features["king.castle_rights_lost"] == %{"white" => false, "black" => false}

    assert features["king.shield"] == %{
             "white" => ~w(d2 e2 f2),
             "black" => ~w(d7 e7 f7)
           }

    assert features["king.missing_shield"] == %{
             "white" => ~w(d3 e3 f3),
             "black" => ~w(d6 e6 f6)
           }

    assert features["king.open_file"] == %{"white" => false, "black" => false}
    refute features["king.exposed"]["white"]
    assert features["king.zone"]["white"] == ~w(d1 d2 e2 f1 f2)
    assert features["king.attackers"] == %{"white" => [], "black" => []}
    assert features["king.defenders"]["white"] == ~w(b1 c1 d1 f1 g1)
    assert features["king.attack_power"] == %{"white" => 0, "black" => 0}
    assert features["king.escape_squares"]["white"] == []
    assert features["king.limited_escapes"]["white"]
    refute features["king.mating_net"]["white"]
    refute features["king.opposite_side_castling"]
    assert features["king.safety_advantage"] == 0
  end

  test "castled king has a shield and fewer escapes" do
    features = extract("6k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1")

    assert features["king.castled"]["white"]
    assert features["king.castled_kingside"]["white"]
    assert features["king.shield"]["white"] == ~w(f2 g2 h2)
    assert features["king.open_file"]["white"] == false
  end
end
