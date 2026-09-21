defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.GameEvents
  alias Analysis.Games
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
       room: room,
       add_game_error: nil,
       selected_game_id: nil,
       game: nil,
       game_revision: nil,
       current_path: []
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
  def handle_info(
        {:game_changed, game_id},
        %{assigns: %{selected_game_id: game_id}} = socket
      ) do
    case Games.get(game_id) do
      {:ok, game, revision} ->
        {:noreply,
         assign(socket,
           game: game,
           game_revision: revision
         )}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "add_game",
        %{"game" => %{"id" => game_id}},
        socket
      ) do
    case Games.get(game_id) do
      {:ok, _game, _revision} ->
        :ok = Rooms.add_game(socket.assigns.room_id, game_id)

        {:noreply, assign(socket, :add_game_error, nil)}

      :not_found ->
        {:noreply, assign(socket, :add_game_error, "Game not found.")}
    end
  end

  @impl true
  def handle_event(
        "remove_game",
        %{"game_id" => game_id},
        socket
      ) do
    :ok = Rooms.remove_game(socket.assigns.room_id, game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "select_game",
        %{"game_id" => game_id},
        socket
      ) do
    case Games.get(game_id) do
      {:ok, game, revision} ->
        subscribe_to_game(socket, game_id)

        {:noreply,
         assign(socket,
           selected_game_id: game_id,
           game: game,
           game_revision: revision,
           current_path: []
         )}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Room {@room_id}</h1>

      <form id="add-game-form" phx-submit="add_game">
        <input
          type="text"
          name="game[id]"
          placeholder="Game ID"
          required
        />

        <button type="submit">
          Add game
        </button>
      </form>

      <%= if @add_game_error do %>
        <p role="alert">{@add_game_error}</p>
      <% end %>

      <%= if @room.game_ids == [] do %>
        <p>No games in this room.</p>
      <% else %>
        <ul>
          <li :for={game_id <- @room.game_ids}>
            <span>{game_id}</span>

            <button
              id={"select-game-#{game_id}"}
              type="button"
              phx-click="select_game"
              phx-value-game_id={game_id}
            >
              Select
            </button>

            <button
              id={"remove-game-#{game_id}"}
              type="button"
              phx-click="remove_game"
              phx-value-game_id={game_id}
            >
              Remove
            </button>
          </li>
        </ul>

        <%= if @selected_game_id do %>
          <section id="selected-game">
            <h2>Selected game</h2>
            <p id="selected-game-id">{@selected_game_id}</p>
            <p id="selected-game-revision">
              Revision {@game_revision}
            </p>
          </section>
        <% end %>
      <% end %>
    </main>
    """
  end

  defp subscribe_to_game(socket, game_id) do
    if connected?(socket) do
      case socket.assigns.selected_game_id do
        nil ->
          :ok

        ^game_id ->
          :ok

        previous_game_id ->
          :ok = GameEvents.unsubscribe(previous_game_id)
      end

      :ok = GameEvents.subscribe(game_id)
    end

    :ok
  end
end
