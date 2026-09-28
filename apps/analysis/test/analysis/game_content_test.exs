defmodule Analysis.GameContentTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameContent
  alias Analysis.GameStart
  alias Chess.Move
  alias Chess.Square

  test "extracts the canonical chess content of a game" do
    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    game =
      Game.new(
        "game-1",
        42,
        [e4, e5],
        %{
          white: "White",
          black: "Black"
        }
      )

    content = GameContent.from_game(game)

    assert GameContent.initial_position_id(content) == 42
    assert GameContent.moves(content) == [e4, e5]
  end

  test "ignores game id when determining canonical content" do
    moves = [
      move("e2", "e4"),
      move("e7", "e5")
    ]

    game_1 =
      Game.new(
        "game-1",
        42,
        moves
      )

    game_2 =
      Game.new(
        "game-2",
        42,
        moves
      )

    assert GameContent.from_game(game_1) ==
             GameContent.from_game(game_2)
  end

  test "ignores metadata when determining canonical content" do
    moves = [
      move("e2", "e4"),
      move("e7", "e5")
    ]

    game_1 =
      Game.new(
        "game-1",
        42,
        moves,
        %{
          white: "Adolf Anderssen",
          black: "Lionel Kieseritzky",
          event: "London 1851"
        }
      )

    game_2 =
      Game.new(
        "game-2",
        42,
        moves,
        %{
          white: "Player C",
          black: "Player D",
          event: "Groningen 2023"
        }
      )

    assert GameContent.from_game(game_1) ==
             GameContent.from_game(game_2)
  end

  test "ignores move-number context when determining canonical content" do
    moves = [
      move("e7", "e5")
    ]

    game_1 =
      Game.new(
        "game-1",
        42,
        GameStart.new(1),
        moves,
        %{}
      )

    game_2 =
      Game.new(
        "game-2",
        42,
        GameStart.new(37),
        moves,
        %{}
      )

    assert GameContent.from_game(game_1) ==
             GameContent.from_game(game_2)
  end

  test "distinguishes different initial positions" do
    moves = [
      move("e2", "e4")
    ]

    game_1 =
      Game.new(
        "game-1",
        42,
        moves
      )

    game_2 =
      Game.new(
        "game-2",
        43,
        moves
      )

    refute GameContent.from_game(game_1) ==
             GameContent.from_game(game_2)
  end

  test "distinguishes different move sequences" do
    game_1 =
      Game.new(
        "game-1",
        42,
        [
          move("e2", "e4"),
          move("e7", "e5")
        ]
      )

    game_2 =
      Game.new(
        "game-2",
        42,
        [
          move("e2", "e4"),
          move("c7", "c5")
        ]
      )

    refute GameContent.from_game(game_1) ==
             GameContent.from_game(game_2)
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
