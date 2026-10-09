defmodule Features.Catalogue.TacticsTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["tactics.pin"] == %{"white" => [], "black" => []}
    assert features["tactics.absolute_pin"] == %{"white" => [], "black" => []}
    assert features["tactics.relative_pin"] == %{"white" => [], "black" => []}
    assert features["tactics.skewer"] == %{"white" => [], "black" => []}
    assert features["tactics.fork"] == %{"white" => [], "black" => []}
    assert features["tactics.double_attack"] == %{"white" => [], "black" => []}
    assert features["tactics.double_check"] == %{"white" => false, "black" => false}
    assert features["tactics.battery"] == %{"white" => false, "black" => false}
    assert features["tactics.overloaded_piece"] == %{"white" => [], "black" => []}
    assert features["tactics.removal_of_defender"] == %{"white" => [], "black" => []}
    assert features["tactics.loose_piece"] == %{"white" => [], "black" => []}
    assert features["tactics.hanging_piece"] == %{"white" => [], "black" => []}

    assert features["tactics.zwischenzug_possibilities"] ==
             %{"white" => false, "black" => false}

    assert features["tactics.discovered_attack"] == %{
             "white" => ~w(a2 d2 h2),
             "black" => ~w(a7 d7 h7)
           }

    assert features["tactics.xray_attack"] == %{
             "white" => ~w(a7 d7 h7),
             "black" => ~w(a2 d2 h2)
           }

    assert features["tactics.deflection_possibility"] == %{"white" => [], "black" => []}

    assert features["tactics.decoy_possibility"] == %{
             "white" => ~w(b8 c8 d8 f8 g8),
             "black" => ~w(b1 c1 d1 f1 g1)
           }

    assert features["tactics.interference"] == %{
             "white" => ~w(b8 c8 d8 e8 f8 g8),
             "black" => ~w(b1 c1 d1 e1 f1 g1)
           }

    assert features["tactics.clearance"] == %{
             "white" => ~w(b1 c1 d1 e1 f1 g1),
             "black" => ~w(b8 c8 d8 e8 f8 g8)
           }

    assert features["tactics.trapped_piece"] == %{
             "white" => ~w(a1 c1 d1 f1 h1),
             "black" => ~w(a8 c8 d8 f8 h8)
           }
  end

  test "absolute pin: rook pins a knight to its king" do
    features = extract("4r3/8/8/8/4N3/8/8/4K3 b - - 0 1")

    assert features["tactics.pin"] == %{"white" => ~w(e4), "black" => []}
    assert features["tactics.absolute_pin"] == %{"white" => ~w(e4), "black" => []}
    assert features["tactics.relative_pin"] == %{"white" => [], "black" => []}
  end

  test "relative pin: rook pins a knight to its queen" do
    features = extract("4r3/8/8/8/4N3/8/4Q3/4K3 b - - 0 1")

    assert features["tactics.pin"] == %{"white" => ~w(e4), "black" => []}
    assert features["tactics.relative_pin"] == %{"white" => ~w(e4), "black" => []}
    assert features["tactics.absolute_pin"] == %{"white" => [], "black" => []}
  end

  test "the pinned piece is also the discoverer of the queen behind it" do
    features = extract("4r3/8/8/8/4N3/8/4Q3/4K3 b - - 0 1")

    assert features["tactics.discovered_attack"] == %{"white" => ~w(e4), "black" => []}
  end

  test "knight fork on two rooks" do
    features = extract("8/8/8/8/8/8/3n4/1R2KR2 b - - 0 1")

    assert features["tactics.fork"] == %{"white" => [], "black" => ~w(d2)}
  end

  test "discovered check by pawn reveal" do
    features = extract("k7/8/8/8/8/8/P7/R3K3 w - - 0 1")

    assert features["tactics.discovered_attack"] == %{"white" => ~w(a2), "black" => []}
    assert features["tactics.discovered_check"] == %{"white" => ~w(a2), "black" => []}
  end

  test "double check with rook and queen on the king" do
    features = extract("4r3/8/8/8/7q/8/8/4K3 b - - 0 1")

    assert features["tactics.double_check"] == %{"white" => true, "black" => false}
  end
end
