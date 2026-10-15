defmodule Web.HomeLive do
  use Web, :live_view

  alias Analysis.Rooms
  alias Web.DisplayName

  @room_code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @room_code_length 6
  @room_create_attempts 5

  @impl true
  def mount(_params, session, socket) do
    locale = Web.I18n.locale_from_session(session)

    {:ok,
     assign(socket,
       page_title: "OpenChessLab",
       locale: locale,
       theme: Web.BrowserPreferences.theme_from_session(session),
       piece_set: "merida",
       room_code: nil,
       ui_modal: nil,
       tour_step: 1,
       join_code: "",
       join_error: nil,
       create_error: nil,
       library_entries: nil,
       library_cursor: nil,
       library_next_cursor: nil,
       library_editing: nil,
       library_title_error: nil,
       providers: [],
       account_error: nil,
       account_delete_armed: false
     )}
  end

  @impl true
  def handle_event("create-room", params, socket) do
    # A private room needs an authenticated owner; the toggle is only
    # rendered for signed-in users, so an unchecked box stays public.
    owner =
      with "true" <- params["private"],
           %{id: user_id} <- socket.assigns.current_user do
        user_id
      else
        _ -> nil
      end

    case create_room(owner) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{code}")}

      {:error, reason} ->
        {:noreply, assign(socket, create_error: inspect(reason))}
    end
  end

  def handle_event("join-room", %{"code" => code}, socket) do
    code = normalize_code(code)

    case Rooms.get(code) do
      {:ok, _room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{code}")}

      :not_found ->
        {:noreply,
         assign(socket,
           join_code: code,
           join_error: Web.I18n.t("home.joinNotFound", socket.assigns.locale)
         )}
    end
  end

  def handle_event("update-code", %{"code" => code}, socket) do
    {:noreply, assign(socket, join_code: normalize_code(code), join_error: nil)}
  end

  def handle_event("restore-preferences", preferences, socket) do
    socket = restore_locale(socket, preferences["locale"])
    theme = valid_theme(preferences["theme"], socket.assigns.theme)
    piece_set = valid_piece_set(preferences["piece_set"], socket.assigns.piece_set)

    {:noreply, assign(socket, theme: theme, piece_set: piece_set)}
  end

  def handle_event("set-theme", %{"theme" => theme}, socket) do
    theme = valid_theme(theme, socket.assigns.theme)
    {:noreply, socket |> assign(:theme, theme) |> push_event("set-theme", %{theme: theme})}
  end

  def handle_event("set-locale", %{"locale" => locale}, socket) do
    socket = restore_locale(socket, locale)
    {:noreply, push_event(socket, "set-locale", %{locale: socket.assigns.locale})}
  end

  def handle_event("set-piece-set", %{"piece_set" => piece_set}, socket) do
    piece_set = valid_piece_set(piece_set, socket.assigns.piece_set)

    {:noreply,
     socket
     |> assign(:piece_set, piece_set)
     |> push_event("set-piece-set", %{piece_set: piece_set})}
  end

  def handle_event("close-modal", _params, socket), do: {:noreply, assign(socket, :ui_modal, nil)}
  def handle_event("latency-ping", _params, socket), do: {:reply, %{}, socket}

  def handle_event("open-library", _params, socket), do: Web.ShellPanels.open_library(socket)
  def handle_event("open-account", _params, socket), do: Web.ShellPanels.open_account(socket)

  def handle_event("account-delete-change", params, socket),
    do: Web.ShellPanels.account_delete_change(params, socket)

  def handle_event("unlink-provider", %{"provider" => provider}, socket),
    do: Web.ShellPanels.unlink_provider(socket, provider)

  def handle_event("library-" <> event, params, socket),
    do: Web.ShellPanels.handle_library_event(event, params, socket)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The owner's member label is their stable account label, stored once at
  # creation and shown in the private room's member list and presence.
  defp create_room(nil = _owner) do
    create_room(@room_create_attempts, nil, nil)
  rescue
    error -> {:error, error}
  end

  defp create_room(owner) do
    create_room(@room_create_attempts, owner, DisplayName.for_user(owner))
  rescue
    error -> {:error, error}
  end

  defp create_room(0, _owner, _name), do: {:error, :room_code_collisions}

  defp create_room(attempts, owner, name) do
    code = new_room_code()
    opts = if owner, do: [owner: owner, owner_display_name: name], else: []

    case Rooms.create_room(code, opts) do
      {:ok, _room} -> {:ok, code}
      {:error, :already_exists} -> create_room(attempts - 1, owner, name)
      {:error, _reason} = error -> error
    end
  end

  defp new_room_code do
    for <<byte <- :crypto.strong_rand_bytes(@room_code_length)>>,
      into: "",
      do: <<Enum.at(@room_code_alphabet, rem(byte, length(@room_code_alphabet)))>>
  end

  defp normalize_code(code) when is_binary(code) do
    code |> String.trim() |> String.upcase() |> String.slice(0, @room_code_length)
  end

  defp normalize_code(_code), do: ""

  defp restore_locale(socket, locale) when locale in ["en", "nl"] do
    {:ok, _} = Localize.put_locale(locale)
    assign(socket, :locale, locale)
  end

  defp restore_locale(socket, _locale), do: socket

  defp valid_theme(theme, _fallback) when theme in ["system", "light", "dark"], do: theme
  defp valid_theme(_theme, fallback), do: fallback

  defp valid_piece_set(piece_set, _fallback) when piece_set in ["merida", "cburnett"],
    do: piece_set

  defp valid_piece_set(_piece_set, fallback), do: fallback
end
