defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.GameEvents
  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.Node
  alias Analysis.RoomEvents
  alias Analysis.Rooms
  alias Chess.Move
  alias Chess.Square

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
       move_error: nil,
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
        current_path =
          nearest_existing_path(game, socket.assigns.current_path)

        {:noreply,
         assign(socket,
           game: game,
           game_revision: revision,
           current_path: current_path
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
  def handle_event(
        "navigate_child",
        %{"index" => index},
        %{assigns: %{game: game, current_path: path}} = socket
      ) do
    child_index = String.to_integer(index)
    new_path = path ++ [child_index]

    if Game.node_at(game, new_path) do
      {:noreply, assign(socket, :current_path, new_path)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "navigate_parent",
        _params,
        %{assigns: %{current_path: []}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "navigate_parent",
        _params,
        %{assigns: %{current_path: path}} = socket
      ) do
    {:noreply, assign(socket, :current_path, Enum.drop(path, -1))}
  end

  @impl true
  def handle_event(
        "play_move",
        %{"move" => %{"from" => from, "to" => to}},
        socket
      ) do
    with from_square when is_integer(from_square) <-
           Square.from_algebraic(from),
         to_square when is_integer(to_square) <-
           Square.from_algebraic(to) do
      move = Move.new(from_square, to_square)

      play_move(socket, move)
    else
      {:error, :invalid_square} ->
        {:noreply, assign(socket, :move_error, "Invalid square.")}
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
            <p id="current-path">
              Path {inspect(@current_path)}
            </p>
            <form id="play-move-form" phx-submit="play_move">
              <input
                type="text"
                name="move[from]"
                placeholder="From"
                required
              />

              <input
                type="text"
                name="move[to]"
                placeholder="To"
                required
              />

              <button type="submit">
                Play move
              </button>
            </form>

            <%= if @move_error do %>
              <p id="move-error" role="alert">{@move_error}</p>
            <% end %>

            <% current_node = Game.node_at(@game, @current_path) %>

            <button
              :if={@current_path != []}
              id="navigate-parent"
              type="button"
              phx-click="navigate_parent"
            >
              Parent
            </button>

            <button
              :for={{_child, index} <- Enum.with_index(Node.children(current_node))}
              id={"navigate-child-#{index}"}
              type="button"
              phx-click="navigate_child"
              phx-value-index={index}
            >
              Child {index}
            </button>
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

  defp nearest_existing_path(game, path) do
    if Game.node_at(game, path) do
      path
    else
      path
      |> Enum.drop(-1)
      |> then(&nearest_existing_path(game, &1))
    end
  end

  defp play_move(socket, move) do
    case Games.play(
           socket.assigns.selected_game_id,
           socket.assigns.current_path,
           move
         ) do
      {:ok, game, revision, resulting_path} ->
        {:noreply,
         assign(socket,
           game: game,
           game_revision: revision,
           current_path: resulting_path,
           move_error: nil
         )}

      {:error, :illegal_move} ->
        {:noreply, assign(socket, :move_error, "Illegal move.")}

      {:error, :node_not_found} ->
        {:noreply, assign(socket, :move_error, "Position no longer exists.")}

      {:error, :position_not_found} ->
        {:noreply, assign(socket, :move_error, "Position not found.")}

      {:error, :game_not_found} ->
        {:noreply, assign(socket, :move_error, "Game not found.")}

      {:error, :conflict} ->
        {:noreply, assign(socket, :move_error, "Game changed. Try again.")}
    end
  end
end
