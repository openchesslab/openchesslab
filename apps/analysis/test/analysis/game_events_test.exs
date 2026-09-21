defmodule Analysis.GameEventsTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.GameEvents
  alias Analysis.Games
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  setup do
    game_id = "game-#{System.unique_integer([:positive])}"

    %{game_id: game_id}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp insert_game(game_id) do
    position_id =
      Position.starting_position()
      |> PositionStore.append()

    game = Game.new(game_id, position_id)

    {:ok, 1} = Games.insert(game)

    game
  end

  test "publishes an event after a game is changed", %{game_id: game_id} do
    insert_game(game_id)

    assert :ok = GameEvents.subscribe(game_id)

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert_receive {:game_changed, ^game_id}
  end

  test "does not publish an event when the move is illegal", %{
    game_id: game_id
  } do
    insert_game(game_id)

    assert :ok = GameEvents.subscribe(game_id)

    assert {:error, :illegal_move} =
             Games.play(game_id, [], move("e2", "e5"))

    refute_receive {:game_changed, ^game_id}
  end

  test "does not publish an event when the game does not exist", %{
    game_id: game_id
  } do
    assert :ok = GameEvents.subscribe(game_id)

    assert {:error, :game_not_found} =
             Games.play(game_id, [], move("e2", "e4"))

    refute_receive {:game_changed, ^game_id}
  end

  test "events are scoped to the game", %{game_id: game_id} do
    other_game_id = "#{game_id}-other"

    insert_game(game_id)
    insert_game(other_game_id)

    assert :ok = GameEvents.subscribe(game_id)

    assert {:ok, _game, 2, [0]} =
             Games.play(other_game_id, [], move("e2", "e4"))

    refute_receive {:game_changed, ^game_id}
    refute_receive {:game_changed, ^other_game_id}
  end
end
