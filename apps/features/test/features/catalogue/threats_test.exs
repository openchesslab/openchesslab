defmodule Features.Catalogue.ThreatsTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "checking and capturing piece companions list the threatening pieces" do
    # The rook checks along the a-file (Ra8+) and can take the b1 knight.
    features = extract("7k/8/8/8/8/8/8/Rn2K3 w - - 0 1")

    assert features["threats.checks"]["white"] == ["a1"]
    assert features["threats.captures"]["white"] == ["a1"]
    assert features["threats.aantal_checks"]["white"] > 0
    assert features["threats.capture_threats"]["white"] > 0

    # Startpos: nobody threatens anything.
    features = extract(@start)
    assert features["threats.checks"] == %{"white" => [], "black" => []}
    assert features["threats.captures"] == %{"white" => [], "black" => []}
  end

  test "start position" do
    features = extract(@start)

    assert features["threats.check"] == %{"white" => false, "black" => false}
    assert features["threats.aantal_checks"] == %{"white" => 0, "black" => 0}
    assert features["threats.capture_threats"] == %{"white" => 0, "black" => 0}
    assert features["threats.mate_threat"] == %{"white" => false, "black" => false}
    assert features["threats.mating_net"] == %{"white" => false, "black" => false}
    assert features["threats.promotion_threat"] == %{"white" => [], "black" => []}
    assert features["threats.discovered_attack_threat"] == %{"white" => [], "black" => []}
    assert features["threats.fork_threat"] == %{"white" => [], "black" => []}
    assert features["threats.pin_exploitation"] == %{"white" => [], "black" => []}
    assert features["threats.sacrifice_opportunity"] == %{"white" => [], "black" => []}
    assert features["threats.tactical_tension"] == 0
    assert features["threats.forcing_move_density"] == %{"white" => 0.0, "black" => 0.0}
    assert features["threats.aantal_forcing_moves"] == %{"white" => 0, "black" => 0}

    assert features["threats.check_capture_threat_moves"] == %{
             "white" => 0,
             "black" => 0
           }
  end

  test "a checking move is detected" do
    features = extract("4r3/8/8/8/7q/8/8/4K3 b - - 0 1")

    assert features["threats.check"] == %{"white" => true, "black" => false}
    assert features["threats.aantal_checks"]["black"] >= 1
  end

  test "checks are legal moves only, never king-adjacency tricks" do
    # Both kings one square apart with a white pawn between them: neither
    # side has a legal check — capturing the pawn puts the kings adjacent,
    # and every other "check" leaves the mover's own king attacked.
    features = extract("8/8/1KPk4/8/8/8/8/8 b - - 0 1")

    assert features["threats.aantal_checks"] == %{"white" => 0, "black" => 0}
  end

  test "promotion threat on the seventh rank" do
    features = extract("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")

    assert features["threats.promotion_threat"] == %{"white" => ~w(a7), "black" => []}
  end

  test "fork threat includes a king amongst the targets" do
    features = extract("8/8/8/8/8/8/3n4/1R2KR2 b - - 0 1")

    assert features["threats.fork_threat"] == %{"white" => [], "black" => ~w(d2)}
  end

  test "pin exploitation lists enemy absolute pins" do
    features = extract("4r3/8/8/8/4N3/8/8/4K3 b - - 0 1")

    assert features["threats.pin_exploitation"] == %{"white" => [], "black" => ~w(e4)}
  end

  test "discovered attack threat against a rook" do
    features = extract("r7/8/8/8/8/8/N7/R3K3 w - - 0 1")

    assert features["threats.discovered_attack_threat"] == %{"white" => ~w(a2), "black" => []}
  end

  test "sacrifice opportunity for a pawn hitting a defended queen" do
    features = extract("2k1r3/8/8/4q3/3P4/8/8/4K3 w - - 0 1")

    assert features["threats.sacrifice_opportunity"] == %{"white" => ~w(e5), "black" => []}
  end

  test "tactical tension grows with mutual attacks" do
    features = extract("6k1/7p/8/8/8/8/8/1B2K3 w - - 0 1")

    assert features["threats.tactical_tension"] == 2
  end
end
