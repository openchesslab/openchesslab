defmodule Web.AccuracyTest do
  use ExUnit.Case, async: true

  alias Web.Accuracy

  describe "move/2" do
    test "a move that holds or improves is 100" do
      assert Accuracy.move(50, 50) == 100.0
      assert Accuracy.move(50, 70) == 100.0
    end

    test "drops follow the published fitted curve" do
      # lichess.org/page/accuracy: Accuracy% = 103.1668 * exp(-0.04354 * diff) - 3.1669 (+1)
      assert_in_delta Accuracy.move(70, 50), 41.0, 0.5
      assert_in_delta Accuracy.move(70, 30), 15.9, 0.5
    end

    test "the curve is clamped" do
      assert Accuracy.move(100, 0) >= 0.0
      assert Accuracy.move(100, 0) < 1.0
    end
  end

  describe "game/2" do
    test "a flawless game is 100 for both sides" do
      # Both sides improve only on their own moves.
      wins = [50.0, 60.0, 40.0, 60.0]
      assert Accuracy.game(wins, :white) == %{white: 100.0, black: 100.0}
    end

    test "only the side that dropped Win% loses accuracy" do
      # 1. good good?? — black's only move improves for them (white's Win% falls).
      assert %{white: 100.0, black: 100.0} = Accuracy.game([50.0, 50.0, 30.0], :white)

      # The same series from black's perspective: black fumbled it.
      result = Accuracy.game([50.0, 50.0, 70.0], :white)
      assert result.white == 100.0
      assert result.black < 50.0
    end

    test "a huge swing costs more than several small ones (harmonic mean)" do
      # White blunders 40 Win%-points on move 3 in one series, makes two
      # 10-point mistakes in the other.
      blunderer = Accuracy.game([50.0, 50.0, 50.0, 10.0], :white)
      steady = Accuracy.game([50.0, 40.0, 50.0, 40.0], :white)

      assert blunderer.white < steady.white
      assert blunderer.white < 50.0
      assert steady.white > 60.0
    end

    test "games with a single move only score that side" do
      assert %{white: white, black: nil} = Accuracy.game([50.0, 50.0], :white)
      assert white == 100.0
    end

    test "oriented per side: white's drop is scored for white, black's for black" do
      # A drop at an even ply is white's mistake; at an odd ply it is black's.
      result = Accuracy.game([50.0, 50.0, 50.0, 10.0, 40.0], :white)
      assert result.white < 50.0
      assert result.black < 50.0
    end
  end
end
