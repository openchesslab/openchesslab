defmodule Analysis.GameReplayTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameReplay
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  test "resolves the initial position from the game position id" do
    game =
      Game.new(
        "game-1",
        42,
        [move("e2", "e4")]
      )

    parent = self()

    resolver = fn position_id ->
      send(
        parent,
        {:resolved_position, position_id}
      )

      {:ok, Position.starting_position()}
    end

    assert {:ok, [_occurrence]} =
             GameReplay.replay(
               game,
               resolver
             )

    assert_received {:resolved_position, 42}
  end

  test "replays the canonical move sequence" do
    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    game =
      Game.new(
        "game-1",
        42,
        [e4, e5]
      )

    resolver = fn 42 ->
      {:ok, Position.starting_position()}
    end

    assert {:ok,
            [
              {^e4, after_e4},
              {^e5, after_e5}
            ]} =
             GameReplay.replay(
               game,
               resolver
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

  test "returns the missing initial position id" do
    game =
      Game.new(
        "game-1",
        42,
        [move("e2", "e4")]
      )

    assert GameReplay.replay(
             game,
             fn _position_id ->
               :not_found
             end
           ) ==
             {:error, {:position_not_found, 42}}
  end

  test "propagates a position resolver error" do
    game =
      Game.new(
        "game-1",
        42,
        [move("e2", "e4")]
      )

    assert GameReplay.replay(
             game,
             fn _position_id ->
               {:error, :disk_failure}
             end
           ) ==
             {:error, :disk_failure}
  end

  test "returns the ply of an illegal move" do
    game =
      Game.new(
        "game-1",
        42,
        [
          move("e2", "e4"),
          move("e7", "e4")
        ]
      )

    assert GameReplay.replay(
             game,
             fn 42 ->
               {:ok, Position.starting_position()}
             end
           ) ==
             {:error, {:illegal_move, 2}}
  end

  test "replays an empty game" do
    game =
      Game.new(
        "game-1",
        42
      )

    assert GameReplay.replay(
             game,
             fn 42 ->
               {:ok, Position.starting_position()}
             end
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
