defmodule Features.Catalogue.PawnsTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    white_structure =
      Map.new(0..7, fn file -> {file, [1]} end)

    black_structure =
      Map.new(0..7, fn file -> {file, [6]} end)

    assert features["pawns.structure"] == %{
             "white" => white_structure,
             "black" => black_structure
           }

    assert features["pawns.count.per_wing"] == %{
             "white" => %{"queenside" => 4, "kingside" => 4},
             "black" => %{"queenside" => 4, "kingside" => 4}
           }

    assert features["pawns.islands"] == %{"white" => 1, "black" => 1}
    assert features["pawns.isolated"] == %{"white" => [], "black" => []}
    assert features["pawns.iqp"] == %{"white" => [], "black" => []}
    assert features["pawns.backward"] == %{"white" => [], "black" => []}
    assert features["pawns.doubled"] == %{"white" => [], "black" => []}
    assert features["pawns.tripled"] == %{"white" => [], "black" => []}
    assert features["pawns.passed"] == %{"white" => [], "black" => []}
    assert features["pawns.protected_passed"] == %{"white" => [], "black" => []}
    assert features["pawns.connected_passed"] == %{"white" => [], "black" => []}
    assert features["pawns.candidate_passed"] == %{"white" => [], "black" => []}
    assert features["pawns.connected"] == %{"white" => [], "black" => []}
    assert features["pawns.hanging"] == %{"white" => [], "black" => []}
    assert features["pawns.chains"] == %{"white" => [], "black" => []}
    assert features["pawns.chain_bases"] == %{"white" => [], "black" => []}

    assert features["pawns.majority"] == %{"white" => false, "black" => false}
    assert features["pawns.kingside_majority"] == %{"white" => false, "black" => false}
    assert features["pawns.queenside_majority"] == %{"white" => false, "black" => false}
    assert features["pawns.minority"] == %{"white" => false, "black" => false}
    assert features["pawns.minority_attack"] == %{"white" => false, "black" => false}

    assert features["pawns.levers"] == %{"white" => [], "black" => []}
    assert features["pawns.breaks"] == %{"white" => [], "black" => []}
    refute features["pawns.locked"]
    assert features["pawns.open_structure"]
    refute features["pawns.fixed"]

    assert features["pawns.weak"] == %{"white" => [], "black" => []}

    assert features["pawns.weak_undeprotectable"] == %{
             "white" => [],
             "black" => []
           }

    assert features["pawns.advanced"] == %{"white" => [], "black" => []}
    assert features["pawns.overextended"] == %{"white" => [], "black" => []}
    assert features["pawns.rook_behind_passed"] == %{"white" => false, "black" => false}
    assert features["pawns.blockaded_passed"] == %{"white" => [], "black" => []}
    assert features["pawns.blockade_square"] == %{"white" => [], "black" => []}
    assert features["pawns.structure_gap"] == 5.0
    refute features["pawns.single_rank_shift"]
    assert features["pawns.diagonal_displacement"] == %{"white" => false, "black" => false}
    assert features["pawns.count_anomaly"] == %{"white" => 0, "black" => 0}
    assert features["pawns.color_mirrored"]
  end

  test "isolated pawns, islands and IQPs" do
    features = extract("4k3/8/8/8/8/8/P1P5/4K3 w - - 0 1")

    assert features["pawns.isolated"]["white"] == ~w(a2 c2)
    assert features["pawns.iqp"]["white"] == ~w(a2 c2)
    assert features["pawns.islands"] == %{"white" => 2, "black" => 0}
    assert features["pawns.weak"]["white"] == ~w(a2 c2)
    assert features["pawns.backward"]["white"] == ~w(a2 c2)
    assert features["pawns.structure_gap"] == nil
    assert features["pawns.count_anomaly"] == %{"white" => 6, "black" => 8}
    refute features["pawns.color_mirrored"]
  end

  test "doubled and tripled pawns" do
    features = extract("7k/8/8/8/P7/P7/P7/7K w - - 0 1")

    assert features["pawns.doubled"]["white"] == ~w(a2 a3 a4)
    assert features["pawns.tripled"]["white"] == ~w(a2 a3 a4)
    assert features["pawns.tripled"]["black"] == []
    assert features["pawns.diagonal_displacement"]["white"]
    assert features["pawns.count_anomaly"] == %{"white" => 5, "black" => 8}
  end

  test "passed, protected and connected passed pawns" do
    protected = extract("7k/8/8/8/8/8/P7/1P5K w - - 0 1")
    connected = extract("7k/8/2P5/1P6/8/8/8/7K w - - 0 1")

    assert protected["pawns.passed"]["white"] == ~w(b1 a2)
    assert protected["pawns.protected_passed"]["white"] == ["a2"]
    assert protected["pawns.connected"]["white"] == ["a2"]
    assert protected["pawns.chains"]["white"] == [["b1", "a2"]]
    assert protected["pawns.chain_bases"]["white"] == ["b1"]

    assert connected["pawns.passed"]["white"] == ~w(b5 c6)
    assert connected["pawns.connected_passed"]["white"] == ~w(b5 c6)
    assert connected["pawns.chains"]["white"] == [["b5", "c6"]]
    assert connected["pawns.chain_bases"]["white"] == ["b5"]
  end

  test "candidate passed pawn needs a virtual advance" do
    features = extract("8/8/8/2p5/1P6/8/8/4K2k w - - 0 1")

    assert features["pawns.passed"]["white"] == []
    assert features["pawns.candidate_passed"]["white"] == ["b4"]
    assert features["pawns.levers"]["white"] == ["b4"]
    assert features["pawns.levers"]["black"] == ["c5"]
    refute features["pawns.open_structure"]
    refute features["pawns.locked"]
  end

  test "hanging pawns on the central files" do
    features = extract("7k/8/8/8/2PP4/8/8/7K w - - 0 1")

    assert features["pawns.hanging"]["white"] == ~w(c4 d4)
  end

  test "majority, minority and minority attack structure" do
    features = extract("7k/pppp4/8/8/8/8/PPP5/K7 w - - 0 1")

    assert features["pawns.majority"] == %{"white" => false, "black" => true}
    assert features["pawns.minority"] == %{"white" => true, "black" => false}
    assert features["pawns.queenside_majority"] == %{"white" => false, "black" => true}
    assert features["pawns.kingside_majority"] == %{"white" => false, "black" => false}
    assert features["pawns.minority_attack"] == %{"white" => true, "black" => false}
    assert features["pawns.islands"] == %{"white" => 1, "black" => 1}
    assert features["pawns.count_anomaly"] == %{"white" => 5, "black" => 4}
    refute features["pawns.single_rank_shift"]
  end

  test "locked, tension and open structures" do
    locked = extract("4k3/8/8/4p3/4P3/8/8/4K3 w - - 0 1")
    tension = extract("4k3/8/8/4p3/3P4/8/8/4K3 w - - 0 1")
    open = extract("4k3/8/3p4/8/4P3/8/8/4K3 w - - 0 1")

    assert locked["pawns.locked"]
    refute locked["pawns.open_structure"]
    assert locked["pawns.fixed"]
    assert locked["pawns.structure_gap"] == 1.0

    refute tension["pawns.locked"]
    refute tension["pawns.open_structure"]
    assert tension["pawns.levers"]["white"] == ["d4"]
    assert tension["pawns.levers"]["black"] == ["e5"]

    refute open["pawns.locked"]
    assert open["pawns.open_structure"]
    refute open["pawns.fixed"]
    assert open["pawns.structure_gap"] == nil
    assert open["pawns.breaks"]["white"] == ["e4"]
  end

  test "advanced and overextended pawns" do
    defended = extract("4k3/8/8/4P3/3P4/8/8/4K3 w - - 0 1")
    lone = extract("4k3/8/8/4P3/8/8/8/4K3 w - - 0 1")

    assert lone["pawns.advanced"]["white"] == ["e5"]
    assert lone["pawns.overextended"]["white"] == ["e5"]
    assert defended["pawns.advanced"]["white"] == ["e5"]
    assert defended["pawns.overextended"]["white"] == []
    assert defended["pawns.connected"]["white"] == ["e5"]
  end

  test "rook behind passed pawn and blockade" do
    features = extract("4k3/8/4n3/4P3/8/8/8/4RK2 w - - 0 1")

    assert features["pawns.passed"]["white"] == ["e5"]
    assert features["pawns.rook_behind_passed"]["white"]
    refute features["pawns.rook_behind_passed"]["black"]
    assert features["pawns.blockaded_passed"]["white"] == ["e5"]
    assert features["pawns.blockade_square"]["white"] == ["e6"]
    assert features["pawns.blockaded_passed"]["black"] == []
  end

  test "single rank shift against the mirrored structure" do
    features = extract("7k/8/8/2p5/8/2P5/8/7K w - - 0 1")

    assert features["pawns.single_rank_shift"]
    assert features["pawns.structure"]["white"][2] == [2]
    assert features["pawns.structure"]["black"][2] == [4]
  end
end
