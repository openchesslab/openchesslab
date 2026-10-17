defmodule Analysis.RoomsTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.Rooms
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users

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

    on_exit(fn -> RoomStore.delete(room_id) end)

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

  test "creating a new room never reuses an existing room code", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    assert {:ok, created} = Rooms.create_room(room_id, rooms_options)
    assert created.id == room_id
    assert :ok = Rooms.add_analysis(room_id, "analysis-1", rooms_options)

    assert {:error, :already_exists} = Rooms.create_room(room_id, rooms_options)
    assert {:ok, existing} = Rooms.get(room_id, rooms_options)
    assert existing.analysis_ids == ["analysis-1"]
  end

  test "only one concurrent creator can claim a room code", %{room_id: room_id} do
    results =
      1..8
      |> Task.async_stream(fn _ -> RoomStore.create(room_id) end,
        max_concurrency: 8,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_exists})) == 7
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

  test "removing an analysis keeps it while another room references it", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    id = "removal-" <> Ecto.UUID.generate()
    second_room = room_id <> "-second"
    {:ok, _analysis, 1} = Analyses.create(id)

    on_exit(fn ->
      RoomStore.delete(second_room)
      OpenChessLab.Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
    end)

    start_room_and_wait(room_id, rooms_options)
    start_room_and_wait(second_room, rooms_options)
    :ok = Rooms.add_analysis(room_id, id, rooms_options)
    :ok = Rooms.add_analysis(second_room, id, rooms_options)

    assert :ok = Rooms.remove_analysis(room_id, id, rooms_options)
    # The other room still references it, so the aggregate survives.
    assert {:ok, _, _} = Analyses.get(id)
    assert {:ok, room} = Rooms.get(room_id, rooms_options)
    assert room.analysis_ids == []

    assert :ok = Rooms.remove_analysis(second_room, id, rooms_options)
    # Nothing references it any more: removing took the aggregate with it.
    assert :not_found = Analyses.get(id)
  end

  test "removing an analysis keeps it while a library entry references it", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    id = "removal-" <> Ecto.UUID.generate()
    {:ok, _analysis, 1} = Analyses.create(id)
    {:ok, user} = Users.create()

    on_exit(fn ->
      OpenChessLab.Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
      Users.delete(user.id)
    end)

    start_room_and_wait(room_id, rooms_options)
    :ok = Rooms.add_analysis(room_id, id, rooms_options)
    assert {:ok, :tracked} = UserLibrary.track_from_room(user.id, room_id, id)

    assert :ok = Rooms.remove_analysis(room_id, id, rooms_options)
    # The live library reference keeps the analysis itself alive.
    assert {:ok, _, _} = Analyses.get(id)
    assert UserLibrary.list(user.id) == [id]
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

  test "pruning an old empty room terminates its worker", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(room_id, rooms_options)

    OpenChessLab.Repo.query!(
      "UPDATE rooms SET created_at = now() - INTERVAL '40 days' WHERE id = $1",
      [room_id]
    )

    [{pid, _value}] = Horde.Registry.lookup(@registry, room_id)
    ref = Process.monitor(pid)

    assert room_id in Rooms.prune_old_empty_rooms(30, 1_000, rooms_options)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    assert :not_found = RoomStore.get(room_id)
    assert :not_found = Rooms.get(room_id, rooms_options)
  end

  test "pruning keeps rooms with analyses", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(room_id, rooms_options)
    assert :ok = Rooms.add_analysis(room_id, "analysis-1", rooms_options)

    OpenChessLab.Repo.query!(
      "UPDATE rooms SET created_at = now() - INTERVAL '40 days' WHERE id = $1",
      [room_id]
    )

    refute room_id in Rooms.prune_old_empty_rooms(30, 1_000, rooms_options)
    assert {:ok, room} = Rooms.get(room_id, rooms_options)
    assert room.analysis_ids == ["analysis-1"]
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

  test "restarts a crashed room with durable memberships and fresh ephemeral chat", %{
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
    assert room.analysis_ids == ["analysis-1"]
    assert {:ok, []} = Rooms.chat(room_id, rooms_options)

    [{new_pid, _value}] =
      Horde.Registry.lookup(
        @registry,
        room_id
      )

    assert new_pid != pid
  end

  test "restores a room with its analysis links when no worker is running", %{
    room_id: room_id,
    rooms_options: rooms_options
  } do
    start_room_and_wait(room_id, rooms_options)
    assert :ok = Rooms.add_analysis(room_id, "analysis-1", rooms_options)
    assert :ok = Rooms.add_analysis(room_id, "analysis-2", rooms_options)

    [{pid, _value}] = Horde.Registry.lookup(@registry, room_id)
    assert :ok = Horde.DynamicSupervisor.terminate_child(@supervisor, pid)

    assert {:ok, restored} = eventually_get_room(room_id, rooms_options)
    assert restored.analysis_ids == ["analysis-1", "analysis-2"]

    assert {:ok, restarted} = Rooms.start_room(room_id, rooms_options)
    assert restarted.analysis_ids == restored.analysis_ids
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

    assert :not_found = RoomStore.get(room_id)
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
