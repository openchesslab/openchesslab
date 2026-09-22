defmodule Analysis.TransitionNotationTest do
  use ExUnit.Case, async: true

  alias Analysis.Transition
  alias Analysis.TransitionNotation
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  test "formats a move transition using canonical SAN" do
    position = Position.starting_position()

    transition =
      Transition.move(
        Move.new(
          Square.from_algebraic("e2"),
          Square.from_algebraic("e4")
        )
      )

    assert TransitionNotation.format(position, transition) ==
             {:ok, "e4"}
  end

  test "edit transitions do not have chess notation" do
    position = Position.starting_position()

    assert TransitionNotation.format(
             position,
             Transition.edit()
           ) == :not_applicable
  end
end
