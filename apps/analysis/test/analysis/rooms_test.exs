defmodule Analysis.RoomsTest do
  use ExUnit.Case, async: false

  alias Analysis.Rooms

  @registry Analysis.RoomsTest.Registry
  @supervisor Analysis.RoomsTest.Supervisor

  setup do
    start_supervised!({
      Horde.Registry,
      name: @registry, keys: :unique, members: :auto
    })

    start_supervised!({
      Horde.DynamicSupervisor,
      name: @supervisor, strategy: :one_for_one, members: :auto
    })

    room_id =
      "room-#{System.unique_integer([:positive])}"

    rooms_options = [
      registry: @registry,
      supervisor: @supervisor
    ]

    %{
      room_id: room_id,
      rooms_options: rooms_options
    }
  end

  test "starts a room", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:ok, room} =
             Rooms.start_room(
               room_id,
               rooms_options
             )

    assert room.id == room_id
    assert room.analysis_ids == []
  end

  test "starting an existing room is idempotent", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:ok, room} =
             Rooms.start_room(
               room_id,
               rooms_options
             )

    assert {:ok, same_room} =
             Rooms.start_room(
               room_id,
               rooms_options
             )

    assert same_room == room
  end

  test "gets an existing room", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:ok, started_room} =
             Rooms.start_room(
               room_id,
               rooms_options
             )

    assert {:ok, room} =
             eventually_get_room(
               room_id,
               rooms_options
             )

    assert room == started_room
  end

  test "returns not_found for an unknown room", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert :not_found =
             Rooms.get(
               room_id,
               rooms_options
             )
  end

  test "adds an analysis", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert :ok =
             Rooms.add_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    assert {:ok, room} =
             Rooms.get(
               room_id,
               rooms_options
             )

    assert room.analysis_ids ==
             ["analysis-1"]
  end

  test "removes an analysis", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert :ok =
             Rooms.add_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    assert :ok =
             Rooms.add_analysis(
               room_id,
               "analysis-2",
               rooms_options
             )

    assert :ok =
             Rooms.remove_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    assert {:ok, room} =
             Rooms.get(
               room_id,
               rooms_options
             )

    assert room.analysis_ids ==
             ["analysis-2"]
  end

  test "operations on an unknown room return not_found", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:error, :not_found} =
             Rooms.add_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    assert {:error, :not_found} =
             Rooms.remove_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )
  end

  test "stops a room", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert :ok =
             Rooms.stop_room(
               room_id,
               rooms_options
             )

    assert :ok =
             eventually_room_not_found(
               room_id,
               rooms_options
             )
  end

  test "stopping an unknown room is idempotent", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert :ok =
             Rooms.stop_room(
               room_id,
               rooms_options
             )
  end

  test "restarts a crashed room with fresh ephemeral state", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert :ok =
             Rooms.add_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    [{pid, _value}] =
      Horde.Registry.lookup(
        @registry,
        room_id
      )

    ref =
      Process.monitor(pid)

    Process.exit(
      pid,
      :kill
    )

    assert_receive {
      :DOWN,
      ^ref,
      :process,
      ^pid,
      :killed
    }

    assert {:ok, room} =
             eventually_get_room(
               room_id,
               rooms_options
             )

    assert room.id == room_id
    assert room.analysis_ids == []

    [{new_pid, _value}] =
      Horde.Registry.lookup(
        @registry,
        room_id
      )

    assert new_pid != pid
  end

  test "does not restart an explicitly stopped room", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert :ok =
             Rooms.add_analysis(
               room_id,
               "analysis-1",
               rooms_options
             )

    [{pid, _value}] =
      Horde.Registry.lookup(
        @registry,
        room_id
      )

    ref =
      Process.monitor(pid)

    assert :ok =
             Rooms.stop_room(
               room_id,
               rooms_options
             )

    assert_receive {
      :DOWN,
      ^ref,
      :process,
      ^pid,
      _reason
    }

    assert :ok =
             eventually_room_not_found(
               room_id,
               rooms_options
             )
  end

  test "sends and lists chat messages", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert {:ok, message} =
             Rooms.send_message(
               room_id,
               %{
                 text: "hello",
                 author: "Alice"
               },
               rooms_options
             )

    assert message.text == "hello"

    assert {:ok,
            [
              %{
                text: "hello",
                author: "Alice"
              }
            ]} =
             Rooms.chat(
               room_id,
               rooms_options
             )
  end

  test "reports the region of the room's owner node", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert {:ok, region} =
             Rooms.region(
               room_id,
               rooms_options
             )

    assert is_binary(region)
  end

  test "chat and region of an unknown room return not_found", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:error, :not_found} =
             Rooms.region(
               room_id,
               rooms_options
             )

    assert {:error, :not_found} =
             Rooms.chat(
               room_id,
               rooms_options
             )

    assert {:error, :not_found} =
             Rooms.send_message(
               room_id,
               %{
                 text: "hi",
                 author: "A"
               },
               rooms_options
             )
  end

  test "rejects an empty chat message", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(
      room_id,
      rooms_options
    )

    assert {:error, :empty} =
             Rooms.send_message(
               room_id,
               %{
                 text: "   ",
                 author: "A"
               },
               rooms_options
             )

    assert {:ok, []} =
             Rooms.chat(
               room_id,
               rooms_options
             )
  end

  defp start_room_and_wait(room_id, rooms_options) do
    assert {:ok, started_room} =
             Rooms.start_room(
               room_id,
               rooms_options
             )

    assert {:ok, room} =
             eventually_get_room(
               room_id,
               rooms_options
             )

    assert room == started_room

    room
  end

  defp eventually_get_room(room_id, rooms_options, attempts \\ 50)

  defp eventually_get_room(_room_id, _rooms_options, 0) do
    :not_found
  end

  defp eventually_get_room(room_id, rooms_options, attempts) do
    case Rooms.get(
           room_id,
           rooms_options
         ) do
      {:ok, room} ->
        {:ok, room}

      :not_found ->
        Process.sleep(10)

        eventually_get_room(
          room_id,
          rooms_options,
          attempts - 1
        )
    end
  end

  defp eventually_room_not_found(room_id, rooms_options, attempts \\ 50)

  defp eventually_room_not_found(_room_id, _rooms_options, 0) do
    {:error, :room_still_exists}
  end

  defp eventually_room_not_found(room_id, rooms_options, attempts) do
    case Rooms.get(
           room_id,
           rooms_options
         ) do
      :not_found ->
        :ok

      {:ok, _room} ->
        Process.sleep(10)

        eventually_room_not_found(
          room_id,
          rooms_options,
          attempts - 1
        )
    end
  end
end
