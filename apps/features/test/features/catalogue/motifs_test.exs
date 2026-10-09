defmodule Features.Catalogue.MotifsTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["motifs.greek_gift"] == %{"white" => false, "black" => false}
    assert features["motifs.smothered_mate_motifs"] == %{"white" => false, "black" => false}
    assert features["motifs.rook_sacrifice_against_king"] == %{"white" => false, "black" => false}
    assert features["motifs.exchange_sacrifice"] == %{"white" => [], "black" => []}
    assert features["motifs.clearance_sacrifice"] == %{"white" => false, "black" => false}
    assert features["motifs.deflection"] == %{"white" => [], "black" => []}
    assert features["motifs.overloaded_defender"] == %{"white" => [], "black" => []}
    assert features["motifs.mating_battery"] == %{"white" => false, "black" => false}
    assert features["motifs.f2_f7_attack"] == %{"white" => 0, "black" => 0}

    assert features["motifs.trapped_queen"] == %{
             "white" => ~w(d8),
             "black" => ~w(d1)
           }
  end

  test "back-rank motifs flag kings boxed in behind their pawns" do
    features = extract(@start)

    assert features["motifs.back_rank_motifs"] == %{"white" => true, "black" => true}
  end

  test "greek gift with a bishop raking h7" do
    features = extract("6k1/7p/8/8/8/8/8/1B2K3 w - - 0 1")

    assert features["motifs.greek_gift"] == %{"white" => true, "black" => false}
  end

  test "smothered mate motif with a knight on g8" do
    features = extract("7k/4N3/8/8/8/8/8/6K1 w - - 0 1")

    assert features["motifs.smothered_mate_motifs"] == %{"white" => true, "black" => false}
  end

  test "rook sacrifice against the h-pawn shelter" do
    features = extract("6k1/R6p/8/8/8/8/8/4K3 w - - 0 1")

    assert features["motifs.rook_sacrifice_against_king"] == %{"white" => true, "black" => false}
  end

  test "exchange sacrifice with a rook on a defended minor" do
    features = extract("4k3/1R5n/8/8/8/8/8/4K3 w - - 0 1")

    assert features["motifs.exchange_sacrifice"] == %{"white" => ~w(h7), "black" => []}
  end

  test "clearance sacrifice with a pawn discoverer against the king" do
    features = extract("k7/8/8/8/8/8/P7/R3K3 w - - 0 1")

    assert features["motifs.clearance_sacrifice"] == %{"white" => true, "black" => false}
  end

  test "mating battery of queen and rook on the h-file" do
    features = extract("7k/8/8/8/7Q/7R/8/6K1 w - - 0 1")

    assert features["motifs.mating_battery"] == %{"white" => true, "black" => false}
  end

  test "f2/f7 attack counts pieces raking the weak squares" do
    features = extract("r1bq1rk1/pppp1ppp/2n2n2/2b1p3/4P3/2P2N2/PP1P1PPP/R1BQKB1R w KQ - 4 6")

    assert features["motifs.f2_f7_attack"]["black"] >= 1
  end
end
