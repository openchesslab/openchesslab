defmodule Analysis.GameReplayTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameReplay
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  test "replays the canonical move sequence" do
    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    game =
      Game.new(
        "game-1",
        1,
        [e4, e5]
      )

    assert {:ok,
            [
              {^e4, after_e4},
              {^e5, after_e5}
            ]} =
             GameReplay.replay(
               game,
               Position.starting_position()
             )

    assert Position.piece_at(
             after_e4,
             Square.from_algebraic("e4")
           ) == {:white, :pawn}

    assert after_e4.side_to_move == :black

    assert Position.piece_at(
             after_e5,
             Square.from_algebraic("e5")
           ) == {:black, :pawn}

    assert after_e5.side_to_move == :white
  end

  test "returns the ply of an illegal move" do
    game =
      Game.new(
        "game-1",
        1,
        [
          move("e2", "e4"),
          move("e7", "e4")
        ]
      )

    assert GameReplay.replay(
             game,
             Position.starting_position()
           ) ==
             {:error, {:illegal_move, 2}}
  end

  test "replays an empty game" do
    game = Game.new("game-1", 1)

    assert GameReplay.replay(
             game,
             Position.starting_position()
           ) ==
             {:ok, []}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
