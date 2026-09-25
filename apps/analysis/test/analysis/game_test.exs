defmodule Analysis.GameTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameStart
  alias Chess.Move
  alias Chess.Square

  test "creates a canonical game with its played moves" do
    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    game =
      Game.new(
        "game-1",
        42,
        [e4, e5],
        %{
          white: "White player",
          black: "Black player",
          result: "1-0"
        }
      )

    assert Game.id(game) == "game-1"
    assert Game.initial_position_id(game) == 42
    assert Game.start(game) == GameStart.standard()
    assert Game.moves(game) == [e4, e5]

    assert Game.metadata(game) == %{
             white: "White player",
             black: "Black player",
             result: "1-0"
           }
  end

  test "creates a game from a non-standard move number" do
    game =
      Game.new(
        "game-1",
        42,
        GameStart.new(37),
        [move("e7", "e5")],
        %{}
      )

    assert Game.start(game) == GameStart.new(37)
  end

  test "creates an empty game" do
    game = Game.new("game-1", 42)

    assert Game.moves(game) == []
    assert Game.metadata(game) == %{}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
