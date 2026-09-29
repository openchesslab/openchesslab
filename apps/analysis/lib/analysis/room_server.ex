defmodule Analysis.RoomServer do
  @moduledoc false

  use GenServer

  alias Analysis.Room
  alias Analysis.RoomChat
  alias Analysis.RoomEvents

  @default_registry Analysis.RoomRegistry

  @type server :: GenServer.server()
  @type registry :: atom()

  @type state :: %{
          room: Room.t(),
          chat: RoomChat.t()
        }

  @spec child_spec(Room.t() | {Room.t(), registry()}) ::
          Supervisor.child_spec()
  def child_spec(%Room{} = room) do
    child_spec({room, @default_registry})
  end

  def child_spec({%Room{} = room, registry})
      when is_atom(registry) do
    %{
      id: {__MODULE__, Room.id(room)},
      start: {
        __MODULE__,
        :start_link,
        [{room, registry}]
      },
      restart: :permanent
    }
  end

  @spec start_link(Room.t() | {Room.t(), registry()}) ::
          GenServer.on_start()
  def start_link(%Room{} = room) do
    start_link({room, @default_registry})
  end

  def start_link({%Room{} = room, registry})
      when is_atom(registry) do
    GenServer.start_link(
      __MODULE__,
      room,
      name:
        via_tuple(
          registry,
          Room.id(room)
        )
    )
  end

  @spec get(server()) :: Room.t()
  def get(server) do
    GenServer.call(
      server,
      :get
    )
  end

  @spec add_analysis(
          server(),
          Room.analysis_id()
        ) :: :ok
  def add_analysis(
        server,
        analysis_id
      ) do
    GenServer.call(
      server,
      {:add_analysis, analysis_id}
    )
  end

  @spec remove_analysis(
          server(),
          Room.analysis_id()
        ) :: :ok
  def remove_analysis(
        server,
        analysis_id
      ) do
    GenServer.call(
      server,
      {:remove_analysis, analysis_id}
    )
  end

  @spec chat(server()) :: [RoomChat.Message.t()]
  def chat(server) do
    GenServer.call(
      server,
      :chat
    )
  end

  @spec send_message(server(), map()) ::
          {:ok, RoomChat.Message.t()}
          | {:error, :empty}
  def send_message(
        server,
        attrs
      ) do
    GenServer.call(
      server,
      {:send_message, attrs}
    )
  end

  @impl true
  def init(%Room{} = room) do
    {:ok,
     %{
       room: room,
       chat: RoomChat.new()
     }}
  end

  @impl true
  def handle_call(
        :get,
        _from,
        %{room: room} = state
      ) do
    {:reply, room, state}
  end

  def handle_call(
        {:add_analysis, analysis_id},
        _from,
        %{room: room} = state
      ) do
    updated_room =
      Room.add_analysis(
        room,
        analysis_id
      )

    publish_if_changed(
      room,
      updated_room
    )

    {:reply, :ok, %{state | room: updated_room}}
  end

  def handle_call(
        {:remove_analysis, analysis_id},
        _from,
        %{room: room} = state
      ) do
    updated_room =
      Room.remove_analysis(
        room,
        analysis_id
      )

    publish_if_changed(
      room,
      updated_room
    )

    {:reply, :ok, %{state | room: updated_room}}
  end

  def handle_call(
        :chat,
        _from,
        %{chat: chat} = state
      ) do
    {:reply, RoomChat.messages(chat), state}
  end

  def handle_call(
        {:send_message, attrs},
        _from,
        %{chat: chat} = state
      ) do
    case RoomChat.send_message(
           chat,
           attrs
         ) do
      {:ok, message, updated_chat} ->
        {:reply, {:ok, message}, %{state | chat: updated_chat}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp publish_if_changed(
         room,
         room
       ),
       do: :ok

  defp publish_if_changed(
         _room,
         updated_room
       ) do
    RoomEvents.publish_changed(Room.id(updated_room))
  end

  defp via_tuple(
         registry,
         room_id
       ) do
    {:via, Horde.Registry, {registry, room_id}}
  end
end
