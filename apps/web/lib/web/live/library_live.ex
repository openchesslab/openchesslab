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
       next_cursor: nil,
       editing: nil,
       title_error: nil
     ), layout: false}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load_page(socket, nil)}

  @impl true
  def handle_event("start-rename", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.entries, &(&1.id == id))
    {:noreply, assign(socket, editing: entry, title_error: nil)}
  end

  def handle_event("cancel-rename", _, socket),
    do: {:noreply, assign(socket, editing: nil, title_error: nil)}

  def handle_event("rename", %{"title" => title}, %{assigns: %{editing: entry}} = socket)
      when not is_nil(entry) do
    case UserLibrary.rename(socket.assigns.current_user.id, entry.id, title) do
      :ok ->
        {:noreply, load_page(socket, socket.assigns.cursor)}

      :not_found ->
        {:noreply, load_page(socket, socket.assigns.cursor)}

      {:error, :invalid_title} ->
        {:noreply,
         assign(socket, :title_error, Web.I18n.t("library.titleInvalid", socket.assigns.locale))}
    end
  end

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

    assign(socket,
      entries: page.entries,
      cursor: cursor,
      next_cursor: page.next_cursor,
      editing: nil,
      title_error: nil
    )
  end
end
