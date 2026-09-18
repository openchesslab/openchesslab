defmodule Analysis.VariationTest do
  use ExUnit.Case, async: true

  alias Analysis.Transition
  alias Analysis.Variation
  alias Chess.Move
  alias Chess.Square

  describe "new/0" do
    test "creates an empty variation" do
      variation = Variation.new()

      assert variation.transitions == []
    end
  end

  describe "new/1" do
    test "stores the transitions in order" do
      move_1 =
        Move.new(
          Square.from_algebraic("e2"),
          Square.from_algebraic("e4")
        )

      move_2 =
        Move.new(
          Square.from_algebraic("e7"),
          Square.from_algebraic("e5")
        )

      transition_1 = Transition.new(1, move_1, 2)
      transition_2 = Transition.new(2, move_2, 3)

      variation = Variation.new([transition_1, transition_2])

      assert variation.transitions == [transition_1, transition_2]
    end

    test "can contain a single transition" do
      move =
        Move.new(
          Square.from_algebraic("e2"),
          Square.from_algebraic("e4")
        )

      transition = Transition.new(1, move, 2)

      variation = Variation.new([transition])

      assert variation.transitions == [transition]
    end
  end
end
