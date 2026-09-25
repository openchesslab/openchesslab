defmodule Web.AnalysesLive do
  use Web, :live_view

  alias Analysis.Analyses
  alias Analysis.Rooms

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       analyses: Analyses.list(),
       open_analysis_error: nil
     )}
  end

  @impl true
  def handle_event(
        "open_analysis",
        %{
          "analysis_id" => analysis_id,
          "room" => %{"id" => room_id}
        },
        socket
      ) do
    case Analyses.get(analysis_id) do
      {:ok, _analysis, _revision} ->
        {:ok, _room} = Rooms.start_room(room_id)
        :ok = Rooms.add_analysis(room_id, analysis_id)

        {:noreply,
         push_navigate(
           socket,
           to: ~p"/rooms/#{room_id}?analysis_id=#{analysis_id}"
         )}

      :not_found ->
        {:noreply,
         assign(
           socket,
           :open_analysis_error,
           gettext("Analysis not found.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>{gettext("Analyses")}</h1>
      
      <%= if @analyses == [] do %>
        <p id="no-analyses">{gettext("No analyses.")}</p>
      <% else %>
        <ul id="analyses">
          <li :for={{analysis, revision} <- @analyses} id={"analysis-#{analysis.id}"}>
            <span class="analysis-id">{analysis.id}</span>
            <span class="analysis-revision">
              {gettext("Revision")} {revision}
            </span>
            
            <form id={"open-analysis-#{analysis.id}"} phx-submit="open_analysis">
              <input
                type="hidden"
                name="analysis_id"
                value={analysis.id}
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
        
        <%= if @open_analysis_error do %>
          <p id="open-analysis-error" role="alert">
            {@open_analysis_error}
          </p>
        <% end %>
      <% end %>
    </main>
    """
  end
end
