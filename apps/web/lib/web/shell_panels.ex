defmodule Web.ShellPanels do
  @moduledoc """
  Library and linked-account shell modal state shared by the home and room LiveViews.

  Modal events stay host-level so `Web.UserAuth` revalidates the browser
  credential before every handler. Each action re-checks the resolved current
  user and fails closed: browser-submitted user, analysis or cursor values
  never select another user's library, and a revoked credential only ever
  renders the guest variant.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Analysis.{Accounts, UserLibrary}
  alias Web.AccountController

  def load_library(socket, cursor \\ nil) do
    # The import modal's My Library tab is the only library surface; it is
    # reachable inside rooms, where entries are branched into room work.
    {:noreply, load(socket, cursor)}
  end

  def open_account(socket) do
    providers =
      if user = socket.assigns.current_user,
        do: Accounts.providers_for(user.id),
        else: []

    {:noreply,
     assign(socket,
       ui_modal: "account",
       providers: providers,
       account_error: nil,
       account_delete_armed: false
     )}
  end

  # Typing the confirmation word arms the deletion button. The server-side
  # check stays authoritative: the disabled button is browser UX only.
  def account_delete_change(params, socket) do
    {:noreply,
     assign(
       socket,
       :account_delete_armed,
       AccountController.confirmation_valid?(params["confirmation"])
     )}
  end

  def unlink_provider(socket, provider) do
    user = socket.assigns.current_user

    if user do
      case Accounts.unlink(user.id, provider) do
        {:ok, _count} ->
          {:noreply,
           assign(socket, providers: Accounts.providers_for(user.id), account_error: nil)}

        {:error, :last_identity} ->
          {:noreply,
           assign(socket, :account_error, Web.I18n.t("auth.unlinkLast", socket.assigns.locale))}

        {:error, _reason} ->
          {:noreply,
           assign(
             socket,
             :account_error,
             Web.I18n.t("auth.unlinkFailed", socket.assigns.locale, %{provider: provider})
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_library_event("start-rename", %{"id" => id}, socket) do
    entry = Enum.find(socket.assigns.library_entries || [], &(&1.id == id))
    {:noreply, assign(socket, library_editing: entry, library_title_error: nil)}
  end

  def handle_library_event("cancel-rename", _params, socket),
    do: {:noreply, assign(socket, library_editing: nil, library_title_error: nil)}

  def handle_library_event(
        "rename",
        %{"title" => title},
        %{assigns: %{current_user: %{id: user_id}, library_editing: entry}} = socket
      )
      when not is_nil(entry) do
    case UserLibrary.rename(user_id, entry.id, title) do
      :ok ->
        {:noreply, load(socket, socket.assigns.library_cursor)}

      :not_found ->
        {:noreply, load(socket, socket.assigns.library_cursor)}

      {:error, :invalid_title} ->
        {:noreply,
         assign(
           socket,
           :library_title_error,
           Web.I18n.t("library.titleInvalid", socket.assigns.locale)
         )}
    end
  end

  def handle_library_event(
        "next-page",
        _params,
        %{assigns: %{library_next_cursor: nil}} = socket
      ),
      do: {:noreply, socket}

  def handle_library_event("next-page", _params, socket),
    do: {:noreply, load(socket, socket.assigns.library_next_cursor)}

  def handle_library_event("first-page", _params, socket), do: {:noreply, load(socket, nil)}

  def handle_library_event(
        "remove",
        %{"id" => id},
        %{assigns: %{current_user: %{id: user_id}}} = socket
      ) do
    UserLibrary.remove(user_id, id)
    {:noreply, load(socket, socket.assigns.library_cursor)}
  end

  def handle_library_event(_event, _params, socket), do: {:noreply, socket}

  defp load(%{assigns: %{current_user: %{id: user_id}}} = socket, cursor) do
    page = UserLibrary.page(user_id, cursor)

    assign(socket,
      library_entries: page.entries,
      library_cursor: cursor,
      library_next_cursor: page.next_cursor,
      library_editing: nil,
      library_title_error: nil
    )
  end

  defp load(socket, _cursor) do
    assign(socket,
      library_entries: [],
      library_cursor: nil,
      library_next_cursor: nil,
      library_editing: nil,
      library_title_error: nil
    )
  end
end
