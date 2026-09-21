defmodule Analysis.GamesTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.Games

  setup do
    game_id = "game-#{System.unique_integer([:positive])}"

    %{game_id: game_id}
  end

  test "gets a stored game", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns not_found for an unknown game", %{game_id: game_id} do
    assert :not_found = Games.get(game_id)
  end

  test "does not insert the same game twice", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)
    assert {:error, :already_exists} = Games.insert(game)
  end
end
