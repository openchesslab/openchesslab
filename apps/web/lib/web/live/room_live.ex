defmodule Web.RoomLive do
  use Web, :live_view

  import Web.ChessComponents

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisEvents
  alias Analysis.Analyses
  alias Analysis.Node
  alias Analysis.RoomChat
  alias Analysis.RoomEvents
  alias Analysis.Rooms
  alias Chess.Position
  alias Chess.PositionDraft
  alias Web.AnalysisView
  alias Web.DemoData
  alias Web.PgnImporter
  alias Web.Presence

  @shape_colors ~w(yellow blue red orange purple)
  @nag_labels %{
    1 => "room.nagGood",
    2 => "room.nagMistake",
    3 => "room.nagBrilliant",
    4 => "room.nagBlunder",
    5 => "room.nagInteresting",
    6 => "room.nagDubious"
  }
  @castling_rights ~w(white_kingside white_queenside black_kingside black_queenside)

  @impl true
  def mount(%{"code" => code}, session, socket) do
    code = String.upcase(code)
    locale = Web.I18n.locale_from_session(session)

    base_assigns = %{
      page_title: Web.I18n.t("room.label", locale) <> " " <> code,
      locale: locale,
      theme: "system",
      piece_set: "merida",
      shape_colors: @shape_colors,
      castling_rights: @castling_rights,
      nag_labels: @nag_labels,
      room_code: code,
      ui_modal: nil,
      tour_step: 1,
      room: nil,
      analyses: [],
      selected_analysis_id: nil,
      subscribed_analysis_id: nil,
      analysis: nil,
      analysis_revision: nil,
      current_path: [],
      mainline_length: 0,
      pending_path: nil,
      current_node: nil,
      position: nil,
      last_from: nil,
      last_to: nil,
      insights: nil,
      move_entries: [],
      move_rows: [],
      move_focus_paths: [],
      move_focus_path: nil,
      selected_square: nil,
      cursor_square: 0,
      legal_targets: [],
      orientation: "white",
      layers: %{files: false, attacks: false, king_zone: false, outposts: false},
      selected_tab: "material",
      strip_open: true,
      annotation_color: "blue",
      annotations: [],
      board_shapes: [],
      participants: %{},
      participant_id: participant_id(),
      display_name: guest_name(),
      joined_at: System.system_time(:second),
      chat_messages: [],
      chat_error: nil,
      local_region: Web.NodeInfo.region(),
      room_region: room_region(code),
      notice: nil,
      error: nil,
      position_editor_open: false,
      edit_mode: false,
      draft_position: nil,
      draft_reasons: [],
      armed_piece: nil,
      remove_armed: false,
      pending_promotion: nil,
      setup_position: Position.starting_position(),
      setup_armed_piece: nil,
      setup_selected_square: nil,
      setup_error: nil,
      pgn: "",
      import_error: nil,
      library_games:
        DemoData.search_games(%{
          "player" => "",
          "color" => "either",
          "result" => "either",
          "opening" => ""
        }),
      search_filters: %{
        "player" => "",
        "color" => "either",
        "result" => "either",
        "opening" => "",
        "date_from" => "",
        "date_to" => "",
        "position_mode" => "exact",
        "fen" => "",
        "substitutions" => ""
      },
      search_results: [],
      provider: nil,
      engine_on: false,
      engine_preview: nil,
      engine_settings_open: false,
      engine_settings: %{depth: 20, movetime_ms: 5000, multipv: 3}
    }

    case Rooms.get(code) do
      {:ok, room} ->
        chat_messages = room_chat(code)

        socket =
          socket
          |> assign(base_assigns)
          |> assign(room: room, analyses: AnalysisView.room_analyses(room, locale))
          |> assign(chat_messages: chat_messages)
          |> stream(:chat_messages, chat_messages)
          |> allow_upload(:pgn,
            accept: ~w(.pgn .txt),
            max_entries: 1,
            max_file_size: 100_000,
            auto_upload: true
          )

        {:ok, subscribe_room(socket)}

      :not_found ->
        {:ok,
         assign(socket, Map.put(base_assigns, :error, Web.I18n.t("home.joinNotFound", locale)))}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    requested_id = params["a"]
    ids = Enum.map(socket.assigns.analyses, & &1.id)

    selected_id =
      cond do
        requested_id in ids -> requested_id
        true -> List.first(ids)
      end

    path =
      cond do
        selected_id == socket.assigns.selected_analysis_id -> socket.assigns.current_path
        is_list(socket.assigns.pending_path) -> socket.assigns.pending_path
        true -> []
      end

    socket =
      socket
      |> subscribe_analysis(selected_id)
      |> assign(:pending_path, nil)
      |> assign(:selected_analysis_id, selected_id)
      |> maybe_load_analysis(selected_id, path)
      |> refresh_presence()

    if selected_id && requested_id != selected_id do
      {:noreply, push_patch(socket, to: analysis_url(socket.assigns.room_code, selected_id))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("restore-preferences", preferences, socket) do
    socket = restore_locale(socket, preferences["locale"])
    theme = valid_theme(preferences["theme"], socket.assigns.theme)
    piece_set = valid_piece_set(preferences["piece_set"], socket.assigns.piece_set)

    annotation_color =
      valid_annotation_color(preferences["annotation_color"], socket.assigns.annotation_color)

    strip_open = preferences["strip_open"] != "false"
    selected_tab = valid_strip_tab(preferences["strip_tab"], socket.assigns.selected_tab)

    {:noreply,
     assign(socket,
       theme: theme,
       piece_set: piece_set,
       annotation_color: annotation_color,
       strip_open: strip_open,
       selected_tab: selected_tab
     )}
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

  def handle_event("open-shortcuts", _params, socket),
    do: {:noreply, assign(socket, :ui_modal, "shortcuts")}

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

  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, ui_modal: nil, engine_settings_open: false)}
  end

  def handle_event("close-promotion", _params, socket),
    do: {:noreply, assign(socket, :pending_promotion, nil)}

  def handle_event("clear-notice", _params, socket), do: {:noreply, assign(socket, :notice, nil)}

  def handle_event("open-import", _params, socket) do
    {:noreply,
     assign(socket,
       ui_modal: "import",
       import_source: "paste",
       pgn: "",
       import_error: nil,
       provider: nil
     )}
  end

  def handle_event("set-import-source", %{"source" => source}, socket)
      when source in ["paste", "library", "lichess", "chesscom"] do
    {:noreply, assign(socket, import_source: source, provider: source)}
  end

  def handle_event("open-search", _params, socket) do
    {:noreply,
     assign(socket,
       ui_modal: "search",
       search_results: [],
       search_filters: %{
         "player" => "",
         "color" => "either",
         "result" => "either",
         "opening" => "",
         "date_from" => "",
         "date_to" => "",
         "position_mode" => "exact",
         "fen" => "",
         "substitutions" => ""
       }
     )}
  end

  def handle_event("open-setup", _params, socket) do
    {:noreply,
     assign(socket,
       ui_modal: "setup",
       setup_position: Position.starting_position(),
       setup_armed_piece: nil,
       setup_selected_square: nil,
       setup_error: nil
     )}
  end

  def handle_event("create-analysis", _params, socket), do: create_analysis(socket, nil)

  def handle_event("select-analysis", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.analyses, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:current_path, [])
       |> push_patch(to: analysis_url(socket.assigns.room_code, id))}
    else
      {:noreply,
       assign(
         socket,
         :notice,
         Web.I18n.t("room.analysisLoadFailed", socket.assigns.locale, %{message: "not found"})
       )}
    end
  end

  def handle_event("follow-viewer", %{"analysis_id" => id, "path" => path}, socket) do
    if Enum.any?(socket.assigns.analyses, &(&1.id == id)) do
      path = parse_path(path)

      if id == socket.assigns.selected_analysis_id do
        {:noreply, select_path(socket, path)}
      else
        {:noreply,
         socket
         |> assign(:pending_path, path)
         |> push_patch(to: analysis_url(socket.assigns.room_code, id))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-path", %{"path" => path}, socket) do
    {:noreply, select_path(socket, parse_path(path))}
  end

  def handle_event("move-tree-key", %{"path" => path, "key" => key}, socket)
      when key in ["ArrowUp", "ArrowDown"] do
    focus_paths = socket.assigns.move_focus_paths

    if focus_paths == [] do
      {:noreply, socket}
    else
      path = parse_path(path)
      current_index = Enum.find_index(focus_paths, &(&1 == path)) || 0

      next_index =
        if key == "ArrowDown",
          do: min(current_index + 1, length(focus_paths) - 1),
          else: max(current_index - 1, 0)

      next_path = Enum.at(focus_paths, next_index)

      {:noreply,
       socket
       |> assign(:move_focus_path, next_path)
       |> push_event("focus-move", %{path: Enum.join(next_path, ",")})}
    end
  end

  def handle_event("move-tree-key", %{"path" => path, "key" => key}, socket)
      when key in ["ArrowLeft", "ArrowRight"] do
    next_path = keyboard_path(socket.assigns.analysis, parse_path(path), key)

    if next_path do
      {:noreply,
       socket
       |> select_path(next_path)
       |> push_event("focus-move", %{path: Enum.join(next_path, ",")})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("first-move", _params, socket), do: {:noreply, select_path(socket, [])}

  def handle_event("previous-move", _params, socket) do
    {:noreply, select_path(socket, Enum.drop(socket.assigns.current_path, -1))}
  end

  def handle_event("next-move", _params, socket) do
    node = socket.assigns.current_node

    if node && Node.children(node) != [] do
      {:noreply, select_path(socket, socket.assigns.current_path ++ [0])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("last-move", _params, socket) do
    root = AnalysisModel.root(socket.assigns.analysis)
    {:noreply, select_path(socket, AnalysisView.mainline_path(root))}
  end

  def handle_event("toggle-orientation", _params, socket) do
    orientation = if socket.assigns.orientation == "white", do: "black", else: "white"
    {:noreply, assign(socket, :orientation, orientation)}
  end

  def handle_event("toggle-layer", %{"layer" => layer}, socket)
      when layer in ["files", "attacks", "king_zone", "outposts"] do
    layers = Map.update!(socket.assigns.layers, String.to_existing_atom(layer), &(!&1))
    {:noreply, assign(socket, :layers, layers)}
  end

  def handle_event("select-strip-tab", %{"tab" => tab}, socket)
      when tab in ["material", "space", "layers"] do
    socket = assign(socket, :selected_tab, tab)
    {:noreply, push_strip_preference(socket)}
  end

  def handle_event("toggle-strip", _params, socket) do
    socket = assign(socket, :strip_open, not socket.assigns.strip_open)
    {:noreply, push_strip_preference(socket)}
  end

  def handle_event("board-square", %{"square" => square}, socket) do
    with {:ok, square} <- parse_square(square) do
      socket = assign(socket, :cursor_square, square)

      cond do
        socket.assigns.ui_modal == "setup" ->
          {:noreply, setup_square(socket, square)}

        socket.assigns.edit_mode or not is_nil(socket.assigns.draft_position) or
          not is_nil(socket.assigns.armed_piece) or socket.assigns.remove_armed ->
          {:noreply, editor_square(socket, square)}

        true ->
          {:noreply, select_or_play_square(socket, square)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("board-cursor", %{"square" => square}, socket) do
    case parse_square(square) do
      {:ok, square} -> {:noreply, assign(socket, :cursor_square, square)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("board-move", %{"from" => from, "to" => to}, socket) do
    with {:ok, from} <- parse_square(from),
         {:ok, to} <- parse_square(to) do
      socket = assign(socket, :cursor_square, to)

      cond do
        socket.assigns.ui_modal == "setup" ->
          {:noreply, setup_move(socket, from, to)}

        socket.assigns.edit_mode or not is_nil(socket.assigns.draft_position) or
          not is_nil(socket.assigns.armed_piece) or socket.assigns.remove_armed ->
          {:noreply, editor_move(socket, from, to)}

        true ->
          maybe_play_move(socket, from, to, nil)
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("promote-pawn", %{"promotion" => promotion}, socket) do
    case {socket.assigns.pending_promotion, promotion_kind(promotion)} do
      {%{from: from, to: to}, kind} when not is_nil(kind) ->
        socket = assign(socket, :pending_promotion, nil)
        maybe_play_move(socket, from, to, kind)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("promote-variation", _params, socket) do
    with id when is_binary(id) <- socket.assigns.selected_analysis_id,
         path when path != [] <- socket.assigns.current_path,
         {:ok, analysis, revision, next_path} <-
           Analyses.promote(id, path) do
      socket = update_analysis(socket, analysis, revision, next_path)

      if next_path == path do
        # already the mainline child: nothing moved, so don't claim success
        {:noreply, socket}
      else
        {:noreply, notify(socket, Web.I18n.t("room.variationPromoted", socket.assigns.locale))}
      end
    else
      _ ->
        {:noreply,
         notify(socket, Web.I18n.t("room.promoteFailed", socket.assigns.locale), :error)}
    end
  end

  def handle_event("remove-subtree", _params, socket) do
    with id when is_binary(id) <- socket.assigns.selected_analysis_id,
         path when path != [] <- socket.assigns.current_path,
         {:ok, analysis, revision, next_path} <-
           Analyses.remove(id, path) do
      {:noreply,
       socket
       |> update_analysis(analysis, revision, next_path)
       |> notify(Web.I18n.t("room.variationRemoved", socket.assigns.locale))}
    else
      _ ->
        {:noreply, notify(socket, Web.I18n.t("room.removeFailed", socket.assigns.locale), :error)}
    end
  end

  def handle_event("save-comment", %{"comment" => comment}, socket) do
    with id when is_binary(id) <- socket.assigns.selected_analysis_id,
         {:ok, analysis, revision} <-
           Analyses.set_comment(
             id,
             socket.assigns.current_path,
             String.trim(comment)
           ) do
      {:noreply,
       socket
       |> update_analysis(analysis, revision, socket.assigns.current_path)
       |> notify(Web.I18n.t("room.savedComment", socket.assigns.locale))}
    else
      _ ->
        {:noreply,
         notify(socket, Web.I18n.t("room.commentFailed", socket.assigns.locale), :error)}
    end
  end

  def handle_event("toggle-nag", %{"nag" => nag}, socket) do
    with {nag, ""} when nag in 0..255 <- Integer.parse(nag),
         %Node{} = node <- socket.assigns.current_node,
         id when is_binary(id) <- socket.assigns.selected_analysis_id do
      current = current_nags(node)
      next = if nag in current, do: [], else: [nag]

      case Analyses.set_nags(id, socket.assigns.current_path, next) do
        {:ok, analysis, revision} ->
          {:noreply, update_analysis(socket, analysis, revision, socket.assigns.current_path)}

        _ ->
          {:noreply,
           notify(socket, Web.I18n.t("room.annotationFailed", socket.assigns.locale), :error)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle-position-editor", _params, socket) do
    open? = not socket.assigns.position_editor_open
    {:noreply, assign(socket, position_editor_open: open?, edit_mode: open?)}
  end

  def handle_event("arm-piece", %{"piece" => piece}, socket) do
    {:noreply, assign(socket, armed_piece: piece, remove_armed: false)}
  end

  def handle_event("arm-remove", _params, socket) do
    {:noreply, assign(socket, armed_piece: nil, remove_armed: not socket.assigns.remove_armed)}
  end

  def handle_event("palette-drop", %{"piece" => piece, "square" => square}, socket) do
    with {:ok, square} <- parse_square(square),
         {:ok, decoded} <- Position.decode_piece(piece) do
      {:noreply,
       assign(socket,
         armed_piece: piece,
         remove_armed: false,
         draft_position: place_or_remove_same_piece(draft_position(socket), square, decoded),
         selected_square: nil,
         draft_reasons: []
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set-castling-right", %{"right" => right}, socket)
      when right in @castling_rights do
    draft = draft_position(socket)
    right = String.to_existing_atom(right)

    rights =
      if MapSet.member?(draft.castling_rights, right),
        do: MapSet.delete(draft.castling_rights, right),
        else: MapSet.put(draft.castling_rights, right)

    {:noreply, assign(socket, :draft_position, %{draft | castling_rights: rights})}
  end

  def handle_event("set-en-passant", %{"square" => square}, socket) do
    draft = draft_position(socket)

    case parse_algebraic(square) do
      {:ok, value} ->
        {:noreply, assign(socket, :draft_position, %{draft | en_passant: value})}

      :none ->
        {:noreply, assign(socket, :draft_position, %{draft | en_passant: nil})}

      :error ->
        {:noreply, notify(socket, Web.I18n.t("room.badEnPassant", socket.assigns.locale), :error)}
    end
  end

  def handle_event("flip-side-to-move", _params, socket) do
    draft = draft_position(socket)
    side = if draft.side_to_move == :white, do: :black, else: :white
    {:noreply, assign(socket, :draft_position, %{draft | side_to_move: side})}
  end

  def handle_event("apply-pending-edit", _params, socket) do
    case {socket.assigns.selected_analysis_id, socket.assigns.draft_position} do
      {id, %Position{} = draft} when is_binary(id) ->
        case Analyses.edit(
               id,
               socket.assigns.current_path,
               PositionDraft.new(draft)
             ) do
          {:ok, analysis, revision, path} ->
            {:noreply,
             socket
             |> assign(
               draft_position: nil,
               draft_reasons: [],
               armed_piece: nil,
               remove_armed: false
             )
             |> update_analysis(analysis, revision, path)}

          {:error, {:invalid_position, reasons}} ->
            {:noreply, assign(socket, :draft_reasons, reasons)}

          {:error, reason} ->
            {:noreply, notify(socket, inspect(reason), :error)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("discard-pending-edit", _params, socket) do
    {:noreply,
     assign(socket, draft_position: nil, draft_reasons: [], armed_piece: nil, remove_armed: false)}
  end

  def handle_event("annotation-color", %{"color" => color}, socket) when color in @shape_colors do
    {:noreply,
     socket
     |> assign(:annotation_color, color)
     |> push_event("set-annotation-color", %{color: color})}
  end

  def handle_event("board-annotation", params, socket) do
    color = params["color"]

    if color in @shape_colors do
      shape = parse_shape(params, color)

      if shape do
        annotations = update_shapes(socket.assigns.annotations, shape)
        {:noreply, socket |> assign(:annotations, annotations) |> refresh_presence()}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear-annotations", _params, socket) do
    {:noreply, socket |> assign(:annotations, []) |> refresh_presence()}
  end

  def handle_event("send-chat", %{"message" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      attrs = %{
        text: text,
        author: socket.assigns.display_name,
        author_id: socket.assigns.participant_id,
        analysis_id: socket.assigns.selected_analysis_id,
        path: socket.assigns.current_path
      }

      case Rooms.send_message(socket.assigns.room_code, attrs) do
        {:ok, message} ->
          payload = RoomChat.to_wire(message)

          Phoenix.PubSub.broadcast(
            Web.PubSub,
            room_topic(socket.assigns.room_code),
            {:chat_message, payload}
          )

          {:noreply, assign(socket, :chat_error, nil)}

        {:error, :empty} ->
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, :chat_error, inspect(reason))}
      end
    end
  end

  def handle_event("toggle-engine", _params, socket) do
    on? = not socket.assigns.engine_on

    preview =
      if on? and socket.assigns.position,
        do: DemoData.engine_preview(socket.assigns.position),
        else: nil

    {:noreply,
     assign(socket,
       engine_on: on?,
       engine_preview: preview,
       engine_settings_open: false
     )}
  end

  def handle_event("open-engine-settings", _params, socket),
    do: {:noreply, assign(socket, :engine_settings_open, true)}

  def handle_event("close-engine-settings", _params, socket),
    do: {:noreply, assign(socket, :engine_settings_open, false)}

  def handle_event("update-engine-settings", params, socket) do
    settings =
      Enum.reduce(["depth", "movetime_ms", "multipv"], socket.assigns.engine_settings, fn key,
                                                                                          acc ->
        case Integer.parse(params[key] || "") do
          {value, ""} when value > 0 ->
            {minimum, maximum} = engine_setting_bounds(key)

            Map.put(
              acc,
              String.to_existing_atom(key),
              value |> max(minimum) |> min(maximum)
            )

          _ ->
            acc
        end
      end)

    {:noreply, assign(socket, :engine_settings, settings)}
  end

  def handle_event("search-games", params, socket) do
    results = DemoData.search_games(params)
    {:noreply, assign(socket, search_filters: params, search_results: results)}
  end

  def handle_event("mock-provider-search", %{"provider" => provider, "query" => query}, socket) do
    results =
      DemoData.search_games(%{
        "player" => query,
        "opening" => "",
        "color" => "either",
        "result" => "either"
      })

    {:noreply,
     socket
     |> assign(provider: provider, search_results: results)
     |> notify(Web.I18n.t("demo.providerNote", socket.assigns.locale))}
  end

  def handle_event("open-demo-game", %{"id" => id}, socket) do
    game = Enum.find(socket.assigns.library_games, &(&1.id == id)) || DemoData.game(id)

    case game do
      %{pgn: pgn} ->
        import_pgn(socket, pgn)

      _ ->
        {:noreply,
         notify(
           socket,
           Web.I18n.t("room.demoGameNotFound", socket.assigns.locale),
           :error
         )}
    end
  end

  def handle_event("use-sample-pgn", _params, socket) do
    sample = DemoData.game("demo-ruy-lopez").pgn
    {:noreply, assign(socket, pgn: sample, import_error: nil)}
  end

  def handle_event("validate-pgn-upload", %{"pgn_text" => pgn}, socket),
    do: {:noreply, assign(socket, :pgn, pgn)}

  def handle_event("validate-pgn-upload", _params, socket), do: {:noreply, socket}

  def handle_event("save-pgn-to-library", _params, socket) do
    case PgnImporter.parse(socket.assigns.pgn) do
      {:ok, parsed} ->
        if Enum.any?(socket.assigns.library_games, &(&1.pgn == socket.assigns.pgn)) do
          {:noreply,
           notify(socket, Web.I18n.t("room.libraryDuplicate", socket.assigns.locale), :error)}
        else
          headers = parsed.headers

          game = %{
            id: "local-#{System.unique_integer([:positive])}",
            white: headers["White"] || "Guest",
            black: headers["Black"] || "Guest",
            white_rating: nil,
            black_rating: nil,
            event: headers["Event"] || "Local demo",
            date: headers["Date"] || "",
            result: headers["Result"] || "*",
            opening: "Imported PGN",
            ply_count: length(parsed.moves),
            pgn: socket.assigns.pgn
          }

          {:noreply,
           socket
           |> assign(:library_games, [game | socket.assigns.library_games])
           |> notify(Web.I18n.t("room.savedToLibrary", socket.assigns.locale))}
        end

      {:error, _reason} ->
        {:noreply,
         notify(socket, Web.I18n.t("room.libraryUnparseable", socket.assigns.locale), :error)}
    end
  end

  def handle_event("remove-library-game", %{"id" => id}, socket) do
    games =
      Enum.reject(
        socket.assigns.library_games,
        &(&1.id == id and String.starts_with?(id, "local-"))
      )

    {:noreply, assign(socket, :library_games, games)}
  end

  def handle_event("cancel-pgn-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :pgn, ref)}
  end

  def handle_event("import-pgn", params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :pgn, fn %{path: path}, _entry -> File.read(path) end)

    case List.first(uploaded) do
      pgn when is_binary(pgn) -> import_pgn(socket, pgn)
      {:error, reason} -> {:noreply, assign(socket, import_error: inspect(reason))}
      nil -> import_pgn(socket, params["pgn_text"] || "")
    end
  end

  def handle_event("set-search-filter", params, socket) do
    {:noreply, assign(socket, :search_filters, Map.merge(socket.assigns.search_filters, params))}
  end

  def handle_event("setup-arm-piece", %{"piece" => piece}, socket) do
    {:noreply, assign(socket, setup_armed_piece: piece, setup_selected_square: nil)}
  end

  def handle_event("setup-palette-drop", %{"piece" => piece, "square" => square}, socket) do
    with {:ok, square} <- parse_square(square),
         {:ok, decoded} <- Position.decode_piece(piece) do
      {:noreply,
       assign(socket,
         setup_armed_piece: piece,
         setup_selected_square: nil,
         setup_position:
           place_or_remove_same_piece(socket.assigns.setup_position, square, decoded),
         setup_error: nil
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("setup-clear-board", _params, socket) do
    {:noreply,
     assign(socket, setup_position: Position.new(), setup_error: nil, setup_armed_piece: nil)}
  end

  def handle_event("setup-flip-side", _params, socket) do
    position = socket.assigns.setup_position
    side = if position.side_to_move == :white, do: :black, else: :white
    {:noreply, assign(socket, setup_position: %{position | side_to_move: side}, setup_error: nil)}
  end

  def handle_event("create-from-setup", _params, socket) do
    create_analysis(socket, socket.assigns.setup_position)
  end

  def handle_event("copy-fen", _params, socket) do
    case socket.assigns.position do
      %Position{} = position ->
        {:noreply,
         push_event(socket, "copy-text", %{
           text: to_fen(position),
           notice: Web.I18n.t("common.copied", socket.assigns.locale)
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("copy-pgn", _params, socket) do
    pgn =
      AnalysisView.move_entries(socket.assigns.analysis, "en")
      |> Enum.filter(fn entry -> Enum.all?(entry.path, &(&1 == 0)) end)
      |> Enum.map_join(" ", fn entry -> entry.prefix <> " " <> entry.label end)

    {:noreply,
     push_event(socket, "copy-text", %{
       text: pgn,
       notice: Web.I18n.t("common.copied", socket.assigns.locale)
     })}
  end

  def handle_event("export-image", _params, socket) do
    case socket.assigns.position do
      %Position{} = position ->
        {:noreply,
         push_event(socket, "download-svg", %{
           filename: "openchesslab-position.svg",
           svg: board_svg(position, socket.assigns.orientation)
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("copy-room-link", _params, socket) do
    url = analysis_url(socket.assigns.room_code, socket.assigns.selected_analysis_id)

    {:noreply,
     push_event(socket, "copy-text", %{
       text: url,
       notice: Web.I18n.t("common.copied", socket.assigns.locale)
     })}
  end

  def handle_event("copy-room-code", _params, socket) do
    {:noreply,
     push_event(socket, "copy-text", %{
       text: socket.assigns.room_code,
       notice: Web.I18n.t("common.copied", socket.assigns.locale)
     })}
  end

  def handle_event("clipboard-result", %{"success" => true, "notice" => notice}, socket),
    do: {:noreply, notify(socket, notice)}

  def handle_event("clipboard-result", %{"notice" => notice}, socket),
    do:
      {:noreply,
       notify(
         socket,
         Web.I18n.t("room.copyFailed", socket.assigns.locale) <> " " <> notice,
         :error
       )}

  def handle_event("latency-ping", _params, socket), do: {:reply, %{}, socket}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:room_changed, _room_code}, socket) do
    socket = refresh_room(socket)

    if socket.assigns.selected_analysis_id in Enum.map(socket.assigns.analyses, & &1.id) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(
         selected_analysis_id: nil,
         analysis: nil,
         position: nil,
         current_node: nil,
         last_from: nil,
         last_to: nil,
         current_path: []
       )
       |> push_patch(to: analysis_url(socket.assigns.room_code, nil))}
    end
  end

  def handle_info({:analysis_changed, analysis_id}, socket) do
    if analysis_id == socket.assigns.selected_analysis_id do
      case AnalysisView.fetch_analysis(analysis_id) do
        {:ok, analysis, revision} ->
          path =
            if socket.assigns.analysis && revision > socket.assigns.analysis_revision do
              AnalysisView.newly_added_paths(socket.assigns.analysis, analysis)
              |> case do
                [] ->
                  AnalysisModel.reconcile_path(
                    socket.assigns.analysis,
                    analysis,
                    socket.assigns.current_path
                  )

                paths ->
                  Enum.max_by(paths, &{length(&1), &1})
              end
            else
              socket.assigns.current_path
            end

          socket =
            if path == socket.assigns.current_path,
              do: socket,
              else: assign(socket, :annotations, [])

          {:noreply, set_analysis(socket, analysis, revision, path)}

        :not_found ->
          {:noreply, maybe_load_analysis(socket, analysis_id, socket.assigns.current_path)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_message, message}, socket) do
    {:noreply, stream_chat_message(socket, message)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, refresh_presence_list(socket)}
  end

  def handle_info({:presence_diff, _diff}, socket), do: {:noreply, refresh_presence_list(socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "chat:message", payload: message}, socket) do
    {:noreply, stream_chat_message(socket, message)}
  end

  def handle_info({:clear_notice, id}, socket) do
    if socket.assigns.notice && socket.assigns.notice.id == id do
      {:noreply, assign(socket, :notice, nil)}
    else
      # a newer notice replaced this one; leave it alone
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp subscribe_room(socket) do
    if connected?(socket) do
      code = socket.assigns.room_code
      topic = room_topic(code)
      RoomEvents.subscribe(code)
      Phoenix.PubSub.subscribe(Web.PubSub, topic)

      meta = presence_meta(socket, nil, [])
      _ = Presence.track(self(), topic, socket.assigns.participant_id, meta)
      refresh_presence(socket)
    else
      socket
    end
  end

  defp subscribe_analysis(socket, analysis_id) do
    previous =
      socket.assigns[:subscribed_analysis_id]

    if connected?(socket) and
         previous != analysis_id do
      if previous do
        AnalysisEvents.unsubscribe(previous)
      end

      if analysis_id do
        AnalysisEvents.subscribe(analysis_id)
      end
    end

    assign(
      socket,
      :subscribed_analysis_id,
      analysis_id
    )
  end

  defp maybe_load_analysis(socket, nil, _path) do
    assign(socket,
      analysis: nil,
      analysis_revision: nil,
      current_path: [],
      current_node: nil,
      position: nil,
      last_from: nil,
      last_to: nil,
      insights: nil,
      move_entries: [],
      move_rows: [],
      move_focus_paths: [],
      move_focus_path: nil,
      selected_square: nil,
      legal_targets: [],
      draft_position: nil
    )
  end

  defp maybe_load_analysis(socket, analysis_id, path) do
    case AnalysisView.fetch_analysis(analysis_id) do
      {:ok, analysis, revision} ->
        path = if AnalysisModel.node_at(analysis, path), do: path, else: []
        set_analysis(socket, analysis, revision, path)

      :not_found ->
        assign(socket,
          error:
            Web.I18n.t("room.analysisLoadFailed", socket.assigns.locale, %{message: "not found"}),
          analysis: nil,
          position: nil
        )
    end
  end

  defp last_move_squares(%Node{transition: {:move, %{from: from, to: to}}}), do: {from, to}
  defp last_move_squares(_node), do: {nil, nil}

  defp set_analysis(socket, analysis, revision, path) do
    case AnalysisView.current_position(analysis, path) do
      {:ok, node, position} ->
        move_list = AnalysisView.move_list_data(analysis, socket.assigns.locale)
        mainline_length = length(AnalysisView.mainline_path(AnalysisModel.root(analysis)))
        {last_from, last_to} = last_move_squares(node)

        socket
        |> assign(
          analysis: analysis,
          analysis_revision: revision,
          selected_analysis_id: analysis.id,
          current_path: path,
          mainline_length: mainline_length,
          current_node: node,
          position: position,
          last_from: last_from,
          last_to: last_to,
          insights: AnalysisView.insights(position),
          move_entries: move_list.entries,
          move_rows: move_list.rows,
          move_focus_paths: move_list.focus_paths,
          move_focus_path: path,
          selected_square: nil,
          cursor_square: cursor_for(position),
          legal_targets: [],
          draft_position: nil,
          draft_reasons: [],
          pending_promotion: nil
        )
        |> refresh_presence()

      :not_found ->
        assign(socket,
          error: Web.I18n.t("room.positionUnavailable", socket.assigns.locale),
          analysis: analysis,
          analysis_revision: revision,
          current_path: path,
          current_node: nil,
          position: nil,
          last_from: nil,
          last_to: nil
        )
    end
  end

  defp refresh_room(socket) do
    case Rooms.get(socket.assigns.room_code) do
      {:ok, room} ->
        assign(socket,
          room: room,
          analyses: AnalysisView.room_analyses(room, socket.assigns.locale)
        )

      :not_found ->
        assign(socket, room: nil, error: Web.I18n.t("home.joinNotFound", socket.assigns.locale))
    end
  end

  defp create_analysis(socket, position) do
    analysis_id =
      new_analysis_id()

    opts =
      if position do
        [position: position]
      else
        []
      end

    with {:ok, analysis, _revision} <-
           Analyses.create(
             analysis_id,
             opts
           ),
         :ok <-
           Rooms.add_analysis(
             socket.assigns.room_code,
             analysis.id
           ) do
      socket =
        socket
        |> refresh_room()
        |> assign(
          ui_modal:
            if(
              position,
              do: nil,
              else: socket.assigns.ui_modal
            ),
          setup_error: nil
        )

      {:noreply,
       socket
       |> assign(:current_path, [])
       |> push_patch(
         to:
           analysis_url(
             socket.assigns.room_code,
             analysis.id
           )
       )}
    else
      {:error, {:invalid_position, reasons}} ->
        {:noreply,
         assign(
           socket,
           setup_error:
             format_reasons(
               reasons,
               socket.assigns.locale
             )
         )}

      {:error, reason} ->
        {:noreply,
         notify(
           socket,
           inspect(reason),
           :error
         )}
    end
  end

  defp update_analysis(socket, analysis, revision, path) do
    socket
    |> refresh_room()
    |> assign(:selected_analysis_id, analysis.id)
    |> set_analysis(analysis, revision, path)
  end

  defp select_path(socket, path) do
    case socket.assigns.analysis do
      %AnalysisModel{} = analysis ->
        if AnalysisModel.node_at(analysis, path) do
          socket
          |> set_analysis(analysis, socket.assigns.analysis_revision, path)
          |> assign(:annotations, [])
        else
          socket
        end

      _ ->
        socket
    end
  end

  defp keyboard_path(%AnalysisModel{} = _analysis, path, "ArrowLeft") when path != [],
    do: Enum.drop(path, -1)

  defp keyboard_path(%AnalysisModel{} = analysis, path, "ArrowRight") do
    case AnalysisModel.node_at(analysis, path) do
      %Node{} = node -> if(Node.children(node) == [], do: nil, else: path ++ [0])
      _ -> nil
    end
  end

  defp keyboard_path(_analysis, _path, _key), do: nil

  defp select_or_play_square(socket, square) do
    selected = socket.assigns.selected_square

    cond do
      selected && selected != square && square in socket.assigns.legal_targets ->
        case maybe_play_move(socket, selected, square, nil) do
          {:noreply, next_socket} -> next_socket
        end

      selected == square ->
        assign(socket, selected_square: nil, legal_targets: [])

      selectable_piece?(socket.assigns.position, square) ->
        targets =
          socket.assigns.position
          |> Position.legal_moves()
          |> Enum.filter(&(&1.from == square))
          |> Enum.map(& &1.to)
          |> Enum.uniq()

        assign(socket, selected_square: square, legal_targets: targets)

      true ->
        assign(socket, selected_square: nil, legal_targets: [])
    end
  end

  defp maybe_play_move(socket, from, to, promotion) do
    position = socket.assigns.position

    moves =
      position
      |> Position.legal_moves()
      |> Enum.filter(&(&1.from == from and &1.to == to))

    cond do
      moves == [] ->
        {:noreply,
         socket
         |> assign(selected_square: nil, legal_targets: [])
         |> notify(Web.I18n.t("room.illegalMove", socket.assigns.locale), :error)}

      promotion == nil and Enum.any?(moves, & &1.promotion) ->
        {:noreply,
         assign(socket,
           pending_promotion: %{
             from: from,
             to: to,
             side: elem(Position.piece_at(position, from), 0)
           },
           selected_square: nil,
           legal_targets: []
         )}

      true ->
        move = Enum.find(moves, &(&1.promotion == promotion)) || hd(moves)

        case Analyses.play(
               socket.assigns.selected_analysis_id,
               socket.assigns.current_path,
               move
             ) do
          {:ok, analysis, revision, path} ->
            {:noreply,
             socket
             |> assign(annotations: [], pending_promotion: nil)
             |> update_analysis(analysis, revision, path)
             |> assign(:cursor_square, to)}

          {:error, reason} ->
            message =
              if reason == :illegal_move,
                do: Web.I18n.t("room.illegalMove", socket.assigns.locale),
                else: inspect(reason)

            {:noreply, notify(socket, message, :error)}
        end
    end
  end

  defp import_pgn(socket, pgn) when is_binary(pgn) do
    record_id =
      new_game_record_id()

    case PgnImporter.import_game(
           record_id,
           pgn
         ) do
      {:ok, record} ->
        case create_imported_analysis(
               socket,
               record.id
             ) do
          {:ok, analysis_id} ->
            socket =
              refresh_room(socket)

            {:noreply,
             socket
             |> assign(
               ui_modal: nil,
               pgn: pgn,
               import_error: nil,
               current_path: []
             )
             |> push_patch(
               to:
                 analysis_url(
                   socket.assigns.room_code,
                   analysis_id
                 )
             )
             |> notify(
               Web.I18n.plural(
                 "room.importedCount",
                 1,
                 %{message: ""}
               )
             )}

          {:error, reason} ->
            {:noreply,
             assign(
               socket,
               import_error:
                 Web.I18n.t(
                   "room.importFailed",
                   socket.assigns.locale,
                   %{
                     message: inspect(reason)
                   }
                 )
             )}
        end

      {:error,
       {
         :invalid_pgn,
         message
       }} ->
        {:noreply,
         assign(
           socket,
           import_error:
             Web.I18n.t(
               "room.parseError",
               socket.assigns.locale,
               %{
                 message: message
               }
             )
         )}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           import_error:
             Web.I18n.t(
               "room.importFailed",
               socket.assigns.locale,
               %{
                 message: inspect(reason)
               }
             )
         )}
    end
  end

  defp create_imported_analysis(socket, game_record_id) do
    analysis_id =
      new_analysis_id()

    with {:ok, analysis, _revision} <-
           Analyses.create_from_game_record(
             analysis_id,
             game_record_id
           ),
         :ok <-
           Rooms.add_analysis(
             socket.assigns.room_code,
             analysis.id
           ) do
      {:ok, analysis.id}
    end
  end

  defp setup_square(socket, square) do
    cond do
      socket.assigns.setup_armed_piece == "remove" ->
        assign(socket,
          setup_position: Position.remove_piece(socket.assigns.setup_position, square),
          setup_error: nil
        )

      socket.assigns.setup_armed_piece ->
        case Position.decode_piece(socket.assigns.setup_armed_piece) do
          {:ok, piece} ->
            position = place_or_remove_same_piece(socket.assigns.setup_position, square, piece)
            assign(socket, setup_position: position, setup_error: nil)

          _ ->
            socket
        end

      socket.assigns.setup_selected_square == square ->
        position = Position.remove_piece(socket.assigns.setup_position, square)

        assign(socket,
          setup_position: position,
          setup_selected_square: nil,
          setup_error: nil
        )

      is_integer(socket.assigns.setup_selected_square) ->
        setup_move(socket, socket.assigns.setup_selected_square, square)

      not is_nil(Position.piece_at(socket.assigns.setup_position, square)) ->
        assign(socket, :setup_selected_square, square)

      true ->
        assign(socket, :setup_selected_square, nil)
    end
  end

  defp setup_move(socket, from, to) do
    position = socket.assigns.setup_position

    case Position.piece_at(position, from) do
      nil ->
        socket

      piece ->
        position = position |> Position.remove_piece(from) |> Position.put_piece(to, piece)
        assign(socket, setup_position: position, setup_selected_square: nil, setup_error: nil)
    end
  end

  defp editor_square(socket, square) do
    position = draft_position(socket)

    cond do
      socket.assigns.remove_armed ->
        assign(socket, draft_position: Position.remove_piece(position, square), draft_reasons: [])

      socket.assigns.armed_piece ->
        case Position.decode_piece(socket.assigns.armed_piece) do
          {:ok, piece} ->
            assign(socket,
              draft_position: place_or_remove_same_piece(position, square, piece),
              selected_square: nil,
              draft_reasons: []
            )

          _ ->
            socket
        end

      socket.assigns.selected_square == square ->
        assign(socket,
          draft_position: Position.remove_piece(position, square),
          selected_square: nil,
          draft_reasons: []
        )

      is_integer(socket.assigns.selected_square) ->
        editor_move(socket, socket.assigns.selected_square, square)

      not is_nil(Position.piece_at(position, square)) ->
        assign(socket, selected_square: square)

      true ->
        assign(socket, selected_square: nil)
    end
  end

  defp editor_move(socket, from, to) do
    position = draft_position(socket)

    case Position.piece_at(position, from) do
      nil ->
        assign(socket, selected_square: nil)

      piece ->
        position =
          position
          |> Position.remove_piece(from)
          |> Position.remove_piece(to)
          |> Position.put_piece(to, piece)

        assign(socket, draft_position: position, selected_square: nil, draft_reasons: [])
    end
  end

  defp place_or_remove_same_piece(position, square, piece) do
    if Position.piece_at(position, square) == piece,
      do: Position.remove_piece(position, square),
      else: Position.put_piece(position, square, piece)
  end

  defp draft_position(socket), do: socket.assigns.draft_position || socket.assigns.position

  defp refresh_presence(socket) do
    if connected?(socket) and socket.assigns.participant_id do
      meta =
        presence_meta(socket, socket.assigns.selected_analysis_id, socket.assigns.current_path)

      _ =
        Presence.update(
          self(),
          room_topic(socket.assigns.room_code),
          socket.assigns.participant_id,
          meta
        )
    end

    refresh_presence_list(socket)
  end

  defp refresh_presence_list(socket) do
    socket = assign(socket, :participants, presence_entries(socket.assigns.room_code))
    assign(socket, :board_shapes, board_shapes(socket))
  end

  defp presence_meta(socket, analysis_id, path) do
    %{
      display_name: socket.assigns.display_name,
      joined_at: socket.assigns.joined_at,
      analysis_id: analysis_id,
      path: path,
      shapes: socket.assigns.annotations
    }
  end

  defp presence_entries(room_code) do
    Presence.list(room_topic(room_code))
    |> Enum.reduce(%{}, fn
      {id, %{metas: [meta | _rest]}}, entries -> Map.put(entries, id, meta)
      _entry, entries -> entries
    end)
  end

  defp room_chat(room_code) do
    case Rooms.chat(room_code) do
      {:ok, messages} -> Enum.map(messages, &RoomChat.to_wire/1)
      _ -> []
    end
  end

  defp append_chat(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)) do
      messages
    else
      Enum.take(messages ++ [message], -200)
    end
  end

  defp stream_chat_message(socket, message) do
    if Enum.any?(socket.assigns.chat_messages, &(&1.id == message.id)) do
      socket
    else
      messages = append_chat(socket.assigns.chat_messages, message)

      socket
      |> assign(:chat_messages, messages)
      |> stream_insert(:chat_messages, message, at: -1, limit: -200)
    end
  end

  defp update_shapes(shapes, %{type: :arrow, from: from, to: to} = shape) do
    if from == to do
      shapes
    else
      [shape | Enum.reject(shapes, &(&1.type == :arrow and &1.from == from and &1.to == to))]
      |> Enum.take(32)
    end
  end

  defp update_shapes(shapes, %{type: :square, square: square} = shape) do
    case Enum.find(shapes, &(&1.type == :square and &1.square == square)) do
      %{color: color} when color == shape.color ->
        Enum.reject(shapes, &(&1.type == :square and &1.square == square))

      _ ->
        [shape | Enum.reject(shapes, &(&1.type == :square and &1.square == square))]
        |> Enum.take(32)
    end
  end

  defp parse_shape(%{"type" => "arrow", "from" => from, "to" => to}, color) do
    with {:ok, from} <- parse_square(from),
         {:ok, to} <- parse_square(to),
         true <- from != to do
      %{type: :arrow, from: from, to: to, color: color}
    else
      _ -> nil
    end
  end

  defp parse_shape(%{"type" => "square", "square" => square}, color) do
    case parse_square(square) do
      {:ok, square} -> %{type: :square, square: square, color: color}
      _ -> nil
    end
  end

  defp parse_shape(_params, _color), do: nil

  defp board_shapes(socket) do
    remote =
      socket.assigns.participants
      |> Enum.flat_map(fn {id, meta} ->
        if id != socket.assigns.participant_id and
             meta.analysis_id == socket.assigns.selected_analysis_id and
             meta.path == socket.assigns.current_path do
          Enum.map(meta.shapes || [], fn shape -> Map.put(shape, :author, meta.display_name) end)
        else
          []
        end
      end)

    remote ++ socket.assigns.annotations
  end

  defp selectable_piece?(%Position{} = position, square) do
    case Position.piece_at(position, square) do
      {color, _kind} -> color == position.side_to_move
      _ -> false
    end
  end

  defp cursor_for(position) do
    position
    |> Position.pieces()
    |> Enum.find_value(fn
      {square, {side, _kind}} when side == position.side_to_move -> square
      _ -> nil
    end)
    |> case do
      nil -> 0
      square -> square
    end
  end

  defp room_region(code) do
    case Rooms.region(code) do
      {:ok, region} -> region
      _ -> nil
    end
  end

  defp region_badge(region) when region in [nil, "local"], do: "⌂"
  defp region_badge("lhr"), do: "🇬🇧"
  defp region_badge("ams"), do: "🇳🇱"
  defp region_badge("fra"), do: "🇩🇪"
  defp region_badge("iad"), do: "🇺🇸"
  defp region_badge("syd"), do: "🇦🇺"
  defp region_badge(region), do: region

  @notice_info_ms 4_000
  @notice_error_ms 8_000

  defp notify(socket, message, level \\ :info) do
    id = System.unique_integer([:positive])
    timeout = if level == :error, do: @notice_error_ms, else: @notice_info_ms
    Process.send_after(self(), {:clear_notice, id}, timeout)

    assign(socket, :notice, %{
      message: message,
      level: level,
      id: id
    })
  end

  defp format_reasons(reasons, locale) do
    Enum.map_join(reasons, ", ", fn reason ->
      key =
        case reason do
          :invalid_white_king_count -> "reason.kingCount"
          :invalid_black_king_count -> "reason.kingCount"
          :adjacent_kings -> "reason.adjacentKings"
          :pawn_on_back_rank -> "reason.pawnOnBackRank"
          :inactive_king_in_check -> "reason.inactiveKingInCheck"
          :invalid_castling_rights -> "reason.castlingRights"
          :invalid_en_passant -> "reason.enPassant"
          :too_many_pawns -> "reason.tooManyPawns"
          :impossible_promotions -> "reason.impossiblePromotions"
          :invalid_side_to_move -> "reason.sideToMove"
          _ -> "reason.noPiece"
        end

      Web.I18n.t(key, locale)
    end)
  end

  defp upload_error_message(:too_large, locale), do: Web.I18n.t("room.importTooLarge", locale)
  defp upload_error_message(:not_accepted, locale), do: Web.I18n.t("room.importBadType", locale)
  defp upload_error_message(:too_many_files, locale), do: Web.I18n.t("room.importBadType", locale)
  defp upload_error_message(_error, locale), do: Web.I18n.t("room.importBadType", locale)

  defp restore_locale(socket, locale) when locale in ["en", "nl"] do
    {:ok, _} = Localize.put_locale(locale)

    socket = assign(socket, :locale, locale)

    socket =
      case socket.assigns.analysis do
        %AnalysisModel{} = analysis ->
          move_list = AnalysisView.move_list_data(analysis, locale)

          assign(socket,
            move_entries: move_list.entries,
            move_rows: move_list.rows,
            move_focus_paths: move_list.focus_paths
          )

        _ ->
          socket
      end

    refresh_room(socket)
  end

  defp restore_locale(socket, _locale), do: socket

  defp valid_theme(theme, _fallback) when theme in ["system", "light", "dark"], do: theme
  defp valid_theme(_theme, fallback), do: fallback

  defp valid_piece_set(piece_set, _fallback) when piece_set in ["merida", "cburnett"],
    do: piece_set

  defp valid_piece_set(_piece_set, fallback), do: fallback

  defp valid_annotation_color(color, _fallback) when color in @shape_colors, do: color
  defp valid_annotation_color(_color, fallback), do: fallback

  defp valid_strip_tab(tab, _fallback) when tab in ["material", "space", "layers"], do: tab
  defp valid_strip_tab(_tab, fallback), do: fallback

  defp push_strip_preference(socket) do
    push_event(socket, "set-strip-preference", %{
      open: socket.assigns.strip_open,
      tab: socket.assigns.selected_tab
    })
  end

  defp parse_square(value) when is_integer(value) and value in 0..63, do: {:ok, value}

  defp parse_square(value) when is_binary(value) do
    case Integer.parse(value) do
      {square, ""} when square in 0..63 -> {:ok, square}
      _ -> :error
    end
  end

  defp parse_square(_value), do: :error

  defp parse_algebraic(value) when is_binary(value) do
    value = String.downcase(String.trim(value))

    cond do
      value == "" ->
        :none

      byte_size(value) != 2 ->
        :error

      true ->
        <<file, rank>> = value
        if file in ?a..?h and rank in ?1..?8, do: {:ok, (rank - ?1) * 8 + file - ?a}, else: :error
    end
  end

  defp parse_algebraic(_value), do: :error

  defp parse_path(path) when is_list(path), do: Enum.filter(path, &(is_integer(&1) and &1 >= 0))

  defp parse_path(path) when is_binary(path) do
    path
    |> String.split(",", trim: true)
    |> Enum.map(&Integer.parse/1)
    |> Enum.flat_map(fn
      {value, ""} when value >= 0 -> [value]
      _ -> []
    end)
  end

  defp parse_path(_path), do: []

  defp promotion_kind("queen"), do: :queen
  defp promotion_kind("rook"), do: :rook
  defp promotion_kind("bishop"), do: :bishop
  defp promotion_kind("knight"), do: :knight
  defp promotion_kind(_), do: nil

  defp analysis_url(code, nil), do: "/rooms/#{URI.encode(code)}"
  defp analysis_url(code, id), do: "/rooms/#{URI.encode(code)}?a=#{URI.encode(id)}"
  defp room_topic(code), do: "room:#{code}"

  defp participant_id, do: "lv-" <> Base.encode16(:crypto.strong_rand_bytes(8))
  defp guest_name, do: "Guest " <> Base.encode16(:crypto.strong_rand_bytes(2))

  defp to_fen(position) do
    board =
      for rank <- Enum.to_list(7..0//-1) do
        {parts, empty} =
          Enum.reduce(0..7, {[], 0}, fn file, {parts, empty} ->
            case Position.piece_at(position, rank * 8 + file) do
              nil ->
                {parts, empty + 1}

              {color, kind} ->
                piece = fen_piece(kind, color)

                parts =
                  if empty > 0,
                    do: [piece, Integer.to_string(empty) | parts],
                    else: [piece | parts]

                {parts, 0}
            end
          end)

        parts = if empty > 0, do: [Integer.to_string(empty) | parts], else: parts
        parts |> Enum.reverse() |> Enum.join()
      end
      |> Enum.join("/")

    side = if position.side_to_move == :white, do: "w", else: "b"
    castling = castling_fen(position.castling_rights)

    en_passant =
      if position.en_passant, do: Chess.Square.to_algebraic(position.en_passant), else: "-"

    "#{board} #{side} #{castling} #{en_passant} 0 1"
  end

  defp fen_piece(kind, :white), do: kind |> fen_letter() |> String.upcase()
  defp fen_piece(kind, :black), do: fen_letter(kind)
  defp fen_letter(:pawn), do: "p"
  defp fen_letter(:knight), do: "n"
  defp fen_letter(:bishop), do: "b"
  defp fen_letter(:rook), do: "r"
  defp fen_letter(:queen), do: "q"
  defp fen_letter(:king), do: "k"

  defp castling_fen(rights) do
    rights = MapSet.new(rights)

    value =
      Enum.map(
        [
          {:white_kingside, "K"},
          {:white_queenside, "Q"},
          {:black_kingside, "k"},
          {:black_queenside, "q"}
        ],
        fn {right, letter} -> if MapSet.member?(rights, right), do: letter, else: "" end
      )
      |> Enum.join()

    if value == "", do: "-", else: value
  end

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp analysis_viewers(analysis_id, participants, participant_id) do
    Enum.count(participants, fn {id, meta} ->
      id != participant_id and meta.analysis_id == analysis_id
    end)
  end

  defp chat_context(message, analyses) do
    case Enum.find(analyses, &(&1.id == message.analysis_id)) do
      nil ->
        nil

      analysis ->
        suffix = if message.path in [nil, []], do: "", else: " · #{length(message.path)}"
        analysis.label <> suffix
    end
  end

  defp region_tooltip(local, room, locale) do
    Web.I18n.t("room.regionTooltip", locale, %{
      you: region_name(local, locale),
      room: region_name(room || local, locale)
    })
  end

  defp region_name(region, locale) when region in [nil, "local"],
    do: Web.I18n.t("room.regionLocal", locale)

  defp region_name(region, _locale), do: region

  defp side_name(:white, "nl"), do: "wit"
  defp side_name(:black, "nl"), do: "zwart"
  defp side_name(:white, _locale), do: "White"
  defp side_name(:black, _locale), do: "Black"

  defp piece_palette do
    for color <- [:white, :black],
        kind <- [:king, :queen, :rook, :bishop, :knight, :pawn],
        do: {color, kind}
  end

  defp piece_name(kind, color, "nl") do
    names = %{
      pawn: "pion",
      knight: "paard",
      bishop: "loper",
      rook: "toren",
      queen: "dame",
      king: "koning"
    }

    side_name(color, "nl") <> " " <> Map.fetch!(names, kind)
  end

  defp piece_name(kind, color, _locale) do
    names = %{
      pawn: "pawn",
      knight: "knight",
      bishop: "bishop",
      rook: "rook",
      queen: "queen",
      king: "king"
    }

    side_name(color, "en") <> " " <> Map.fetch!(names, kind)
  end

  defp piece_glyph(:king, :white), do: "♔"
  defp piece_glyph(:queen, :white), do: "♕"
  defp piece_glyph(:rook, :white), do: "♖"
  defp piece_glyph(:bishop, :white), do: "♗"
  defp piece_glyph(:knight, :white), do: "♘"
  defp piece_glyph(:pawn, :white), do: "♙"
  defp piece_glyph(:king, :black), do: "♚"
  defp piece_glyph(:queen, :black), do: "♛"
  defp piece_glyph(:rook, :black), do: "♜"
  defp piece_glyph(:bishop, :black), do: "♝"
  defp piece_glyph(:knight, :black), do: "♞"
  defp piece_glyph(:pawn, :black), do: "♟"

  defp board_svg(position, orientation) do
    squares =
      for rank <- if(orientation == "black", do: Enum.to_list(0..7), else: Enum.to_list(7..0//-1)),
          file <- if(orientation == "black", do: Enum.to_list(7..0//-1), else: Enum.to_list(0..7)) do
        square = rank * 8 + file
        {rank, file, square, Position.piece_at(position, square)}
      end

    cells =
      Enum.map(squares, fn {rank, file, square, piece} ->
        {visual_file, visual_rank} = svg_coords(square, orientation)
        fill = if rem(file + rank, 2) == 1, do: "#ebecd0", else: "#779556"
        x = visual_file * 100
        y = visual_rank * 100

        [
          "<rect x=\"#{x}\" y=\"#{y}\" width=\"100\" height=\"100\" fill=\"#{fill}\"/>",
          svg_piece(piece, x, y)
        ]
      end)

    IO.iodata_to_binary([
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"800\" height=\"800\" viewBox=\"0 0 800 800\">",
      cells,
      "</svg>"
    ])
  end

  defp svg_coords(square, "black"), do: {7 - rem(square, 8), div(square, 8)}
  defp svg_coords(square, _orientation), do: {rem(square, 8), 7 - div(square, 8)}

  defp svg_piece(nil, _x, _y), do: ""

  defp svg_piece({color, kind}, x, y) do
    glyph = piece_glyph(kind, color)
    fill = if color == :white, do: "#fff", else: "#17191f"
    stroke = if color == :white, do: "#303030", else: "#ddd"

    "<text x=\"#{x + 50}\" y=\"#{y + 52}\" text-anchor=\"middle\" dominant-baseline=\"central\" font-family=\"DejaVu Sans,serif\" font-size=\"74\" fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"1\">#{glyph}</text>"
  end

  defp castling_label("white_kingside", locale), do: Web.I18n.t("room.whiteKingside", locale)
  defp castling_label("white_queenside", locale), do: Web.I18n.t("room.whiteQueenside", locale)
  defp castling_label("black_kingside", locale), do: Web.I18n.t("room.blackKingside", locale)
  defp castling_label("black_queenside", locale), do: Web.I18n.t("room.blackQueenside", locale)

  defp layer_label_key("files"), do: "room.layerFiles"
  defp layer_label_key("attacks"), do: "room.layerAttacks"
  defp layer_label_key("king_zone"), do: "room.layerKingZone"
  defp layer_label_key("outposts"), do: "room.layerOutposts"

  defp strip_tab_class(selected, tab) do
    base =
      "flex items-center gap-2 border-b-2 px-3 py-2 text-xs font-medium uppercase tracking-wider max-[860px]:py-[.3rem]"

    if selected == tab,
      do: base <> " border-highlight text-highlight",
      else: base <> " border-transparent text-muted hover:text-foreground"
  end

  defp material_total(counts) do
    counts.queen * 9 + counts.rook * 5 + counts.bishop * 3 + counts.knight * 3 + counts.pawn
  end

  defp material_balance(nil), do: "–"

  defp material_balance(insights) do
    balance = material_total(insights.material.white) - material_total(insights.material.black)
    if balance > 0, do: "+#{balance}", else: to_string(balance)
  end

  defp material_text(counts, color, locale) do
    [:queen, :rook, :bishop, :knight, :pawn]
    |> Enum.map(fn kind ->
      count = Map.get(counts, kind, 0)
      if count > 0, do: "#{count}× #{piece_name(kind, color, locale)}", else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "—"
      pieces -> Enum.join(pieces, ", ")
    end
  end

  defp nag_label_key(nag), do: Map.fetch!(@nag_labels, nag)
  defp current_nags(%Node{} = node), do: Enum.take(Node.nags(node), 1)
  defp current_nags(_node), do: []

  defp nag_glyph(1), do: "!"
  defp nag_glyph(2), do: "?"
  defp nag_glyph(3), do: "‼"
  defp nag_glyph(4), do: "⁇"
  defp nag_glyph(5), do: "⁉"
  defp nag_glyph(6), do: "⁈"
  defp nag_glyph(_nag), do: ""

  defp shape_color("yellow"), do: "#f2c200"
  defp shape_color("red"), do: "#d6453d"
  defp shape_color("orange"), do: "#e08a1e"
  defp shape_color("purple"), do: "#8b5cf6"
  defp shape_color(_color), do: "#3b6fe0"

  defp engine_setting_bounds("depth"), do: {1, 40}
  defp engine_setting_bounds("movetime_ms"), do: {100, 100_000}
  defp engine_setting_bounds("multipv"), do: {1, 10}

  defp eval_white_share(%{eval_cp: cp}) when is_number(cp) do
    cp = max(-1000, min(1000, cp))
    Float.round((0.5 + cp / 2000) * 100, 1)
  end

  defp eval_white_share(_preview), do: 50.0

  defp eval_label(%{eval_cp: cp}) when is_number(cp) do
    score = :erlang.float_to_binary(abs(cp) / 100, decimals: 2)
    if cp >= 0, do: "+" <> score, else: "-" <> score
  end

  defp eval_label(_preview), do: "—"

  defp eval_label_position(preview, "black"), do: eval_white_share(preview)
  defp eval_label_position(preview, _orientation), do: 100 - eval_white_share(preview)

  defp eval_fill_style(preview, "black"), do: "height:#{eval_white_share(preview)}%;top:0"
  defp eval_fill_style(preview, _orientation), do: "height:#{eval_white_share(preview)}%;bottom:0"

  defp new_game_record_id do
    "game-record-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end

  defp new_analysis_id do
    "analysis-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end
end
