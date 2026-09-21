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

  test "restarts a crashed room with fresh ephemeral state", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")

    [{pid, _value}] =
      Horde.Registry.lookup(Analysis.RoomRegistry, room_id)

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert {:ok, room} = eventually_get_room(room_id)

    assert room.id == room_id
    assert room.game_ids == []

    [{new_pid, _value}] =
      Horde.Registry.lookup(Analysis.RoomRegistry, room_id)

    assert new_pid != pid
  end

  test "does not restart an explicitly stopped room", %{room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")

    [{pid, _value}] =
      Horde.Registry.lookup(Analysis.RoomRegistry, room_id)

    ref = Process.monitor(pid)

    assert :ok = Rooms.stop_room(room_id)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    assert :ok = eventually_room_not_found(room_id)
  end

  defp eventually_get_room(room_id, attempts \\ 50)

  defp eventually_get_room(_room_id, 0), do: :not_found

  defp eventually_get_room(room_id, attempts) do
    case Rooms.get(room_id) do
      {:ok, room} ->
        {:ok, room}

      :not_found ->
        Process.sleep(10)
        eventually_get_room(room_id, attempts - 1)
    end
  end

  defp eventually_room_not_found(room_id, attempts \\ 50)

  defp eventually_room_not_found(_room_id, 0) do
    {:error, :room_still_exists}
  end

  defp eventually_room_not_found(room_id, attempts) do
    case Rooms.get(room_id) do
      :not_found ->
        :ok

      {:ok, _room} ->
        Process.sleep(10)
        eventually_room_not_found(room_id, attempts - 1)
    end
  end
end
