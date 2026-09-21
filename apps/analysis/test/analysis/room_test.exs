defmodule Analysis.RoomTest do
  use ExUnit.Case, async: true

  alias Analysis.Room

  test "creates an empty room" do
    room = Room.new("room-1")

    assert Room.id(room) == "room-1"
    assert Room.game_ids(room) == []
  end

  test "adds a game" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_game("game-1")

    assert Room.game_ids(room) == ["game-1"]
    assert Room.has_game?(room, "game-1")
  end

  test "adds multiple games in order" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_game("game-1")
      |> Room.add_game("game-2")
      |> Room.add_game("game-3")

    assert Room.game_ids(room) ==
             ["game-1", "game-2", "game-3"]
  end

  test "adding the same game twice is idempotent" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_game("game-1")
      |> Room.add_game("game-1")

    assert Room.game_ids(room) == ["game-1"]
  end

  test "removes a game" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_game("game-1")
      |> Room.add_game("game-2")
      |> Room.remove_game("game-1")

    refute Room.has_game?(room, "game-1")
    assert Room.has_game?(room, "game-2")
    assert Room.game_ids(room) == ["game-2"]
  end

  test "removing an unknown game is idempotent" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_game("game-1")
      |> Room.remove_game("missing")

    assert Room.game_ids(room) == ["game-1"]
  end
end
