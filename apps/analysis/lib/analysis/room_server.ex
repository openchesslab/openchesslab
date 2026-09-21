defmodule Analysis.RoomServer do
  @moduledoc false

  use GenServer

  alias Analysis.Room

  @type server :: GenServer.server()

  @spec start_link(Room.t()) :: GenServer.on_start()
  def start_link(%Room{} = room) do
    GenServer.start_link(__MODULE__, room)
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
    room = Room.add_game(room, game_id)

    {:reply, :ok, room}
  end

  def handle_call({:remove_game, game_id}, _from, room) do
    room = Room.remove_game(room, game_id)

    {:reply, :ok, room}
  end
end
