defmodule Web.HomeLive do
  use Web, :live_view

  alias Analysis.Rooms

  @room_code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @room_code_length 6

  @impl true
  def mount(_params, session, socket) do
    locale = Web.I18n.locale_from_session(session)

    {:ok,
     assign(socket,
       page_title: "OpenChessLab",
       locale: locale,
       theme: "system",
       piece_set: "merida",
       room_code: nil,
       ui_modal: nil,
       tour_step: 1,
       join_code: "",
       join_error: nil,
       create_error: nil
     )}
  end

  @impl true
  def handle_event("create-room", _params, socket) do
    case create_room() do
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

  def handle_event("open-tour", _params, socket),
    do: {:noreply, assign(socket, ui_modal: "tour", tour_step: 1)}

  def handle_event("tour-back", _params, socket),
    do: {:noreply, update(socket, :tour_step, &max(&1 - 1, 1))}

  def handle_event("tour-next", _params, socket) do
    if socket.assigns.tour_step >= Web.Layouts.tour_steps_count() do
      {:noreply, assign(socket, :ui_modal, nil)}
    else
      {:noreply, update(socket, :tour_step, &(&1 + 1))}
    end
  end

  def handle_event("open-shortcuts", _params, socket),
    do: {:noreply, assign(socket, :ui_modal, "shortcuts")}

  def handle_event("close-modal", _params, socket), do: {:noreply, assign(socket, :ui_modal, nil)}
  def handle_event("latency-ping", _params, socket), do: {:reply, %{}, socket}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp create_room do
    code = new_room_code()

    case Rooms.start_room(code) do
      {:ok, _room} -> {:ok, code}
    end
  rescue
    error -> {:error, error}
  end

  defp new_room_code do
    for _ <- 1..@room_code_length,
        into: "",
        do: <<Enum.at(@room_code_alphabet, :rand.uniform(length(@room_code_alphabet)) - 1)>>
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
