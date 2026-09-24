defmodule Web.GamesLive do
  use Web, :live_view

  alias Analysis.Games
  alias Analysis.Rooms

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       games: Games.list(),
       open_game_error: nil
     )}
  end

  @impl true
  def handle_event(
        "open_game",
        %{
          "game_id" => game_id,
          "room" => %{"id" => room_id}
        },
        socket
      ) do
    case Games.get(game_id) do
      {:ok, _game, _revision} ->
        {:ok, _room} = Rooms.start_room(room_id)
        :ok = Rooms.add_game(room_id, game_id)

        {:noreply,
         push_navigate(
           socket,
           to: ~p"/rooms/#{room_id}?game_id=#{game_id}"
         )}

      :not_found ->
        {:noreply,
         assign(
           socket,
           :open_game_error,
           gettext("Game not found.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>{gettext("Games")}</h1>
      
      <%= if @games == [] do %>
        <p id="no-games">{gettext("No games.")}</p>
      <% else %>
        <ul id="games">
          <li :for={{game, revision} <- @games} id={"game-#{game.id}"}>
            <span class="game-id">{game.id}</span>
            <span class="game-revision">
              {gettext("Revision")} {revision}
            </span>
            
            <form id={"open-game-#{game.id}"} phx-submit="open_game">
              <input
                type="hidden"
                name="game_id"
                value={game.id}
              />
              <input
                type="text"
                name="room[id]"
                placeholder={gettext("Room ID")}
                required
              />
              <button type="submit">
                {gettext("Open in room")}
              </button>
            </form>
          </li>
        </ul>
        
        <%= if @open_game_error do %>
          <p id="open-game-error" role="alert">
            {@open_game_error}
          </p>
        <% end %>
      <% end %>
    </main>
    """
  end
end
