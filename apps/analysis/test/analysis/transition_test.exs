defmodule Analysis.TransitionTest do
  use ExUnit.Case, async: true

  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Square

  describe "move/1" do
    test "creates a move transition" do
      move =
        Move.new(
          Square.from_algebraic("e2"),
          Square.from_algebraic("e4")
        )

      assert Transition.move(move) == {:move, move}
    end
  end

  describe "edit/0" do
    test "creates an edit transition" do
      assert Transition.edit() == :edit
    end
  end
end
