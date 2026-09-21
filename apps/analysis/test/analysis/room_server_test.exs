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
    assert Room.game_ids(room) == []
  end

  test "adds a game", %{server: server} do
    assert :ok = RoomServer.add_game(server, "game-1")

    room = RoomServer.get(server)

    assert Room.game_ids(room) == ["game-1"]
  end

  test "removes a game", %{server: server} do
    :ok = RoomServer.add_game(server, "game-1")
    :ok = RoomServer.add_game(server, "game-2")

    assert :ok = RoomServer.remove_game(server, "game-1")

    room = RoomServer.get(server)

    assert Room.game_ids(room) == ["game-2"]
  end

  test "multiple callers observe the same room state", %{server: server} do
    parent = self()

    spawn(fn ->
      :ok = RoomServer.add_game(server, "game-1")
      send(parent, :game_added)
    end)

    assert_receive :game_added

    room = RoomServer.get(server)

    assert Room.game_ids(room) == ["game-1"]
  end

  test "serializes concurrent changes", %{server: server} do
    tasks =
      for game_number <- 1..20 do
        Task.async(fn ->
          RoomServer.add_game(
            server,
            "game-#{game_number}"
          )
        end)
      end

    assert Enum.map(tasks, &Task.await/1) ==
             List.duplicate(:ok, 20)

    room = RoomServer.get(server)

    assert MapSet.new(Room.game_ids(room)) ==
             MapSet.new(
               for game_number <- 1..20 do
                 "game-#{game_number}"
               end
             )
  end
end
