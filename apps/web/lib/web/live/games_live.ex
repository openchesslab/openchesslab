defmodule Web.GamesLive do
  use Web, :live_view

  alias Analysis.Games

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, games: Games.list())}
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
          </li>
        </ul>
      <% end %>
    </main>
    """
  end
end
