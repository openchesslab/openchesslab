defmodule Web.AccountLive do
  use Web, :live_view

  @impl true
  def mount(_params, session, socket) do
    locale = Web.I18n.locale_from_session(session)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: Web.I18n.t("auth.connections", locale),
       providers: []
     ), layout: false}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket, :providers, Analysis.Accounts.providers_for(socket.assigns.current_user.id))}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}
end
