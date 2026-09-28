defmodule Analysis.GameContentTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Chess.Move
  alias Chess.Square

  test "creates canonical game content" do
    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    content =
      GameContent.new(
        42,
        [e4, e5]
      )

    assert GameContent.initial_position_id(content) == 42

    assert GameContent.moves(content) ==
             [e4, e5]
  end

  test "creates empty canonical game content" do
    content =
      GameContent.new(42)

    assert GameContent.initial_position_id(content) == 42

    assert GameContent.moves(content) == []
  end

  test "distinguishes different initial positions" do
    moves = [
      move("e2", "e4")
    ]

    refute GameContent.new(42, moves) ==
             GameContent.new(43, moves)
  end

  test "distinguishes different move sequences" do
    first =
      GameContent.new(
        42,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    second =
      GameContent.new(
        42,
        [
          move("e2", "e4"),
          move("c7", "c5")
        ]
      )

    refute first == second
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
