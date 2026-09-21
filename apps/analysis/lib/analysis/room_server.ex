defmodule Analysis.RoomServer do
  @moduledoc false

  use GenServer

  alias Analysis.Room
  alias Analysis.RoomEvents

  @type server :: GenServer.server()

  @spec child_spec(Room.t()) :: Supervisor.child_spec()
  def child_spec(%Room{} = room) do
    %{
      id: {__MODULE__, Room.id(room)},
      start: {__MODULE__, :start_link, [room]},
      restart: :permanent
    }
  end

  @spec start_link(Room.t()) :: GenServer.on_start()
  def start_link(%Room{} = room) do
    GenServer.start_link(
      __MODULE__,
      room,
      name: via_tuple(Room.id(room))
    )
  end

  @spec get(server()) :: Room.t()
  def get(server) do
    GenServer.call(server, :get)
  end

  @spec add_game(server(), Room.game_id()) :: :ok
  def add_game(server, game_id) do
    GenServer.call(server, {:add_game, game_id})
  end

  @spec remove_game(server(), Room.game_id()) :: :ok
  def remove_game(server, game_id) do
    GenServer.call(server, {:remove_game, game_id})
  end

  @impl true
  def init(%Room{} = room) do
    {:ok, room}
  end

  @impl true
  def handle_call(:get, _from, room) do
    {:reply, room, room}
  end

  def handle_call({:add_game, game_id}, _from, room) do
    updated_room = Room.add_game(room, game_id)

    publish_if_changed(room, updated_room)

    {:reply, :ok, updated_room}
  end

  def handle_call({:remove_game, game_id}, _from, room) do
    updated_room = Room.remove_game(room, game_id)

    publish_if_changed(room, updated_room)

    {:reply, :ok, updated_room}
  end

  defp publish_if_changed(room, room), do: :ok

  defp publish_if_changed(_room, updated_room) do
    RoomEvents.publish_changed(Room.id(updated_room))
  end

  defp via_tuple(room_id) do
    {:via, Horde.Registry, {Analysis.RoomRegistry, room_id}}
  end
end
