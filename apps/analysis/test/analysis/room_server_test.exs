defmodule Analysis.RoomServerTest do
  use ExUnit.Case, async: true

  alias Analysis.Room
  alias Analysis.RoomServer

  setup do
    room = Room.new("room-1")
    {:ok, server} = RoomServer.start_link(room)

    %{server: server}
  end

  test "starts with the supplied room", %{server: server} do
    room = RoomServer.get(server)

    assert Room.id(room) == "room-1"
    assert Room.analysis_ids(room) == []
  end

  test "adds an analysis", %{server: server} do
    assert :ok = RoomServer.add_analysis(server, "analysis-1")

    room = RoomServer.get(server)

    assert Room.analysis_ids(room) == ["analysis-1"]
  end

  test "removes an analysis", %{server: server} do
    :ok = RoomServer.add_analysis(server, "analysis-1")
    :ok = RoomServer.add_analysis(server, "analysis-2")

    assert :ok = RoomServer.remove_analysis(server, "analysis-1")

    room = RoomServer.get(server)

    assert Room.analysis_ids(room) == ["analysis-2"]
  end

  test "multiple callers observe the same room state", %{server: server} do
    parent = self()

    spawn(fn ->
      :ok = RoomServer.add_analysis(server, "analysis-1")
      send(parent, :analysis_added)
    end)

    assert_receive :analysis_added

    room = RoomServer.get(server)

    assert Room.analysis_ids(room) == ["analysis-1"]
  end

  test "serializes concurrent changes", %{server: server} do
    tasks =
      for analysis_number <- 1..20 do
        Task.async(fn ->
          RoomServer.add_analysis(
            server,
            "analysis-#{analysis_number}"
          )
        end)
      end

    assert Enum.map(tasks, &Task.await/1) ==
             List.duplicate(:ok, 20)

    room = RoomServer.get(server)

    assert MapSet.new(Room.analysis_ids(room)) ==
             MapSet.new(
               for analysis_number <- 1..20 do
                 "analysis-#{analysis_number}"
               end
             )
  end
end
