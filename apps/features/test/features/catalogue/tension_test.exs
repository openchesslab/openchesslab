defmodule Features.Catalogue.TensionTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["tension.pawn_tension"] == 0
    assert features["tension.central_tension"] == 0
    assert features["tension.kingside_tension"] == 0
    assert features["tension.queenside_tension"] == 0
    assert features["tension.opposed_pawns"] == 8
    assert features["tension.unresolved_captures"] == 0
    assert features["tension.mutually_attacked_pieces"] == 0
    assert features["tension.lever_structure"] == %{"white" => [], "black" => []}
    assert features["tension.possible_pawn_breaks"] == %{"white" => [], "black" => []}
    assert features["tension.static_versus_dynamic"] == %{"type" => "static"}
  end

  test "mutual pawn tension in the centre" do
    features = extract("4k3/8/4p3/8/2P5/8/8/4K3 w - - 0 1")

    assert features["tension.pawn_tension"] == 1
    assert features["tension.central_tension"] == 1
    assert features["tension.kingside_tension"] == 0
    assert features["tension.queenside_tension"] == 0
  end
end
