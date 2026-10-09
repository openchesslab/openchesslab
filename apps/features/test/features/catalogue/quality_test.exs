defmodule Features.Catalogue.QualityTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["quality.good_bishop"] == %{"white" => [], "black" => []}
    assert features["quality.bad_bishop"] == %{"white" => [], "black" => []}

    assert features["quality.bishop_pawn_color_conflict"] ==
             %{"white" => [4, 4], "black" => [4, 4]}

    assert features["quality.bishop_pair"] == %{"white" => true, "black" => true}
    assert features["quality.opposite_colored_bishops"] == false
    assert features["quality.knight_outpost"] == %{"white" => [], "black" => []}

    assert features["quality.strong_knight_vs_bad_bishop"] == %{
             "white" => false,
             "black" => false
           }

    assert features["quality.active_rook"] == %{"white" => [], "black" => []}

    assert features["quality.passive_rook"] == %{
             "white" => ~w(a1 h1),
             "black" => ~w(a8 h8)
           }

    assert features["quality.queen_activity"] == %{"white" => 0, "black" => 0}
    assert features["quality.piece_coordination"] == %{"white" => 14, "black" => 14}
    assert features["quality.batteries"] == %{"white" => [], "black" => []}
    assert features["quality.connected_rooks"] == %{"white" => false, "black" => false}
    assert features["quality.rooks_cut_off"] == %{"white" => true, "black" => true}
    assert features["quality.piece_harmony"] == %{"white" => 20, "black" => 20}

    assert features["quality.poorly_placed_piece"] == %{
             "white" => ~w(a1 c1 d1 f1 h1),
             "black" => ~w(a8 c8 d8 f8 h8)
           }

    assert features["quality.best_worst_placed"] == %{
             "white" => ~w(b1 a1),
             "black" => ~w(a7 a8)
           }
  end

  test "active rook on an open file" do
    features = extract("4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")

    assert features["quality.active_rook"] == %{"white" => ~w(a1 h1), "black" => []}
    assert features["quality.passive_rook"] == %{"white" => [], "black" => []}
  end

  test "rook on the open f-file is active, rook on a closed file stays passive" do
    features = extract("r1bq1rk1/ppp1p1pp/2np1n2/6NQ/2B1P3/2N5/PP6/R1B2RK1 b - - 0 1")

    assert features["quality.active_rook"] == %{"white" => ~w(f1), "black" => ~w(f8)}
    assert features["quality.passive_rook"] == %{"white" => ~w(a1), "black" => ~w(a8)}
  end

  test "knight outpost and strong knight versus bad bishop" do
    features = extract("2bk4/8/p1pN2p1/4P1pp/P1p5/3P4/8/4K3 w - - 0 1")

    assert features["quality.bad_bishop"] == %{"white" => [], "black" => ~w(c8)}
    assert features["quality.knight_outpost"] == %{"white" => ~w(d6), "black" => []}

    assert features["quality.strong_knight_vs_bad_bishop"] == %{
             "white" => true,
             "black" => false
           }
  end
end
