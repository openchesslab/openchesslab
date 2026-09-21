defmodule Analysis.RoomEventsTest do
  use ExUnit.Case, async: false

  alias Analysis.RoomEvents
  alias Analysis.Rooms

  setup do
    room_id = "room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Rooms.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  test "publishes an event when a game is added", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = RoomEvents.subscribe(room_id)

    assert :ok = Rooms.add_game(room_id, "game-1")

    assert_receive {:room_changed, ^room_id}
  end

  test "does not publish an event when adding an existing game", %{
    room_id: room_id
  } do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")
    assert :ok = RoomEvents.subscribe(room_id)

    assert :ok = Rooms.add_game(room_id, "game-1")

    refute_receive {:room_changed, ^room_id}
  end

  test "publishes an event when a game is removed", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")
    assert :ok = RoomEvents.subscribe(room_id)

    assert :ok = Rooms.remove_game(room_id, "game-1")

    assert_receive {:room_changed, ^room_id}
  end

  test "does not publish an event when removing a missing game", %{
    room_id: room_id
  } do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = RoomEvents.subscribe(room_id)

    assert :ok = Rooms.remove_game(room_id, "game-1")

    refute_receive {:room_changed, ^room_id}
  end

  test "events are scoped to the room", %{room_id: room_id} do
    other_room_id = "#{room_id}-other"

    on_exit(fn ->
      Rooms.stop_room(other_room_id)
    end)

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert {:ok, _room} = Rooms.start_room(other_room_id)

    assert :ok = RoomEvents.subscribe(room_id)

    assert :ok = Rooms.add_game(other_room_id, "game-1")

    refute_receive {:room_changed, ^room_id}
    refute_receive {:room_changed, ^other_room_id}
  end
end
