defmodule Analysis.TransitionTest do
  use ExUnit.Case, async: true

  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Square

  describe "new/3" do
    test "stores the source position id" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      transition = Transition.new(10, move, 11)

      assert transition.from_position_id == 10
    end

    test "stores the move" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      transition = Transition.new(10, move, 11)

      assert transition.move == move
    end

    test "stores the destination position id" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      transition = Transition.new(10, move, 11)

      assert transition.to_position_id == 11
    end

    test "source and destination position ids can differ" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      transition = Transition.new(42, move, 73)

      assert transition.from_position_id != transition.to_position_id
    end

    test "uses Chess.Move directly" do
      move =
        Move.new(
          Square.from_algebraic("e7"),
          Square.from_algebraic("e8"),
          :queen
        )

      transition = Transition.new(1, move, 2)

      assert %Move{} = transition.move
      assert transition.move.from == Square.from_algebraic("e7")
      assert transition.move.to == Square.from_algebraic("e8")
      assert transition.move.promotion == :queen
    end
  end
end
