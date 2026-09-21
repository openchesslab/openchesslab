defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.Rooms

  @impl true
  def mount(%{"room_id" => room_id}, _session, socket) do
    {:ok, room} = Rooms.start_room(room_id)

    {:ok,
     assign(socket,
       room_id: room_id,
       room: room
     )}
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
