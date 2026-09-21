defmodule Analysis.RoomsTest do
  use ExUnit.Case, async: false

  alias Analysis.Rooms

  setup do
    room_id = "room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Rooms.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  test "starts a room", %{room_id: room_id} do
    assert {:ok, room} = Rooms.start_room(room_id)

    assert room.id == room_id
    assert room.game_ids == []
  end

  test "starting an existing room is idempotent", %{room_id: room_id} do
    assert {:ok, room} = Rooms.start_room(room_id)
    assert {:ok, same_room} = Rooms.start_room(room_id)

    assert same_room == room
  end

  test "gets an existing room", %{room_id: room_id} do
    assert {:ok, started_room} = Rooms.start_room(room_id)
    assert {:ok, room} = Rooms.get(room_id)

    assert room == started_room
  end

  test "returns not_found for an unknown room", %{room_id: room_id} do
    assert :not_found = Rooms.get(room_id)
  end

  test "adds a game", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)

    assert :ok = Rooms.add_game(room_id, "game-1")

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == ["game-1"]
  end

  test "removes a game", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)

    assert :ok = Rooms.add_game(room_id, "game-1")
    assert :ok = Rooms.add_game(room_id, "game-2")
    assert :ok = Rooms.remove_game(room_id, "game-1")

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == ["game-2"]
  end

  test "operations on an unknown room return not_found", %{room_id: room_id} do
    assert {:error, :not_found} =
             Rooms.add_game(room_id, "game-1")

    assert {:error, :not_found} =
             Rooms.remove_game(room_id, "game-1")
  end

  test "stops a room", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)

    assert :ok = Rooms.stop_room(room_id)
    assert :not_found = Rooms.get(room_id)
  end

  test "stopping an unknown room is idempotent", %{room_id: room_id} do
    assert :ok = Rooms.stop_room(room_id)
  end
end
