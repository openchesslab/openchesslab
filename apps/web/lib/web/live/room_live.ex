defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.RoomEvents
  alias Analysis.Rooms

  @impl true
  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok, room} = Rooms.start_room(room_id)

    if connected?(socket) do
      :ok = RoomEvents.subscribe(room_id)
    end

    {:ok,
     assign(socket,
       room_id: room_id,
       room: room
     )}
  end

  @impl true
  def handle_info({:room_changed, room_id}, %{assigns: %{room_id: room_id}} = socket) do
    case Rooms.get(room_id) do
      {:ok, room} ->
        {:noreply, assign(socket, :room, room)}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Room {@room_id}</h1>

      <%= if @room.game_ids == [] do %>
        <p>No games in this room.</p>
      <% else %>
        <ul>
          <li :for={game_id <- @room.game_ids}>
            {game_id}
          </li>
        </ul>
      <% end %>
    </main>
    """
  end
end
