defmodule Features.Catalogue.PlacementTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["placement.piece_on_square"]["a1"] == "white rook"
    assert features["placement.piece_on_square"]["e1"] == "white king"
    assert features["placement.piece_on_square"]["e8"] == "black king"
    assert features["placement.type_at_square"]["a1"] == "rook"
    assert features["placement.type_at_square"]["d8"] == "queen"

    assert features["placement.concentration.per_wing"] == %{
             "white" => %{"queenside" => 4, "kingside" => 4},
             "black" => %{"queenside" => 4, "kingside" => 4}
           }

    assert features["placement.center"] == %{"white" => 0, "black" => 0}
    assert features["placement.enemy_territory"] == %{"white" => [], "black" => []}
    assert features["placement.advanced"] == %{"white" => [], "black" => []}
    assert features["placement.centralized"] == %{"white" => [], "black" => []}
    assert features["placement.knight_on_rim"] == %{"white" => [], "black" => []}
    assert features["placement.knight_outpost"] == %{"white" => [], "black" => []}

    assert features["placement.bad_bishop"] == %{
             "white" => ~w(c1 f1),
             "black" => ~w(c8 f8)
           }

    assert features["placement.trapped_rook"] == %{
             "white" => ~w(a1 h1),
             "black" => ~w(a8 h8)
           }

    assert features["placement.rook_seventh"] == %{"white" => [], "black" => []}
    assert features["placement.rook_behind_passed"] == %{"white" => false, "black" => false}
    assert features["placement.rook_open_file"] == %{"white" => [], "black" => []}
    refute features["placement.doubled_rooks"]["white"]
    refute features["placement.connected_rooks"]["white"]
  end

  test "outposts, seventh rank and doubled rooks" do
    features = extract("4k3/8/8/2N5/1P6/8/8/4K3 w - - 0 1")
    assert features["placement.knight_outpost"]["white"] == ~w(c5)

    features = extract("8/R3k3/8/8/8/8/8/4K3 w - - 0 1")
    assert features["placement.rook_seventh"]["white"] == ~w(a7)

    features = extract("4k3/8/8/8/8/8/R7/R3K3 w - - 0 1")
    assert features["placement.doubled_rooks"]["white"]
    assert features["placement.connected_rooks"]["white"]
  end
end
