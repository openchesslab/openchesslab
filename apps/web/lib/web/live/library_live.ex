defmodule Web.LibraryLive do
  use Web, :live_view

  alias Analysis.UserLibrary

  @impl true
  def mount(_params, session, socket) do
    locale = Web.I18n.locale_from_session(session)

    {:ok,
     assign(socket,
       page_title: Web.I18n.t("library.title", locale),
       locale: locale,
       entries: [],
       cursor: nil,
       next_cursor: nil
     ), layout: false}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load_page(socket, nil)}

  @impl true
  def handle_event("next-page", _params, %{assigns: %{next_cursor: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("next-page", _params, socket),
    do: {:noreply, load_page(socket, socket.assigns.next_cursor)}

  def handle_event("first-page", _params, socket), do: {:noreply, load_page(socket, nil)}

  def handle_event("remove", %{"id" => id}, socket) do
    # The credential is revalidated by the required auth hook before this
    # handler. Browser-supplied User IDs can never select the library owner.
    UserLibrary.remove(socket.assigns.current_user.id, id)
    {:noreply, load_page(socket, socket.assigns.cursor)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp load_page(socket, cursor) do
    page = UserLibrary.page(socket.assigns.current_user.id, cursor)
    assign(socket, entries: page.entries, cursor: cursor, next_cursor: page.next_cursor)
  end
end
