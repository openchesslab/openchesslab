defmodule Web.RoomLive do
  use Web, :live_view

  import Web.ChessComponents

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisEvents
  alias Analysis.Analyses
  alias Analysis.GameRecordQuery
  alias Analysis.GameSearch
  alias Analysis.PositionStore
  alias Analysis.Node
  alias Analysis.OpeningBook
  alias Analysis.PgnAnalysisImporter
  alias Analysis.PgnBatchImporter
  alias Analysis.ProviderGrants
  alias Analysis.PositionEvals
  alias Analysis.PositionFeatures
  alias Analysis.PositionTablebases
  alias Analysis.RoomChat
  alias Analysis.RoomEvents
  alias Analysis.Rooms
  alias Analysis.UserLibrary
  alias Chess.Notation.FEN
  alias Chess.Notation.UCI
  alias Chess.Position
  alias Chess.PositionDraft
  alias Chess.Square
  alias Features.Catalogue
  alias Web.AnalysisView
  alias Web.DemoData
  alias Web.Accuracy
  alias Web.DisplayName
  alias Web.GameImport
  alias Web.Presence
  alias Web.Tablebase

  @shape_colors ~w(yellow blue red orange purple)
  @url_sync_debounce_ms 300
  # How many recent Lichess games the import tray lists.
  @provider_recent_games 25
  # The vendored engine build identity; cached evaluations are per engine.
  @engine_id "stockfish-19-lite-single"
  @engine_review_depth 12
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
      theme: Web.BrowserPreferences.theme_from_session(session),
      piece_set: "merida",
      shape_colors: @shape_colors,
      castling_rights: @castling_rights,
      nag_labels: @nag_labels,
      room_code: code,
      ui_modal: nil,
      share_pending_id: nil,
      share_pending_has_game: false,
      tour_step: 1,
      library_entries: nil,
      library_cursor: nil,
      library_next_cursor: nil,
      library_editing: nil,
      library_title_error: nil,
      providers: [],
      lichess_sync: %{enabled: false, synced_at: nil},
      account_error: nil,
      account_delete_armed: false,
      tracked_ids: [],
      private_gate: nil,
      invite_editor_active: false,
      invite_viewer_active: false,
      invite_token: nil,
      invite_url: nil,
      invite_token_role: nil,
      members: [],
      room: nil,
      analyses: [],
      selected_analysis_id: nil,
      subscribed_analysis_id: nil,
      analysis: nil,
      analysis_revision: nil,
      current_path: [],
      mainline_length: 0,
      url_analysis_id: nil,
      url_path: nil,
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
      pinned_features: MapSet.new(),
      removal_pending: nil,
      feature_highlights: %{
        white: MapSet.new(),
        black: MapSet.new(),
        neutral: MapSet.new(),
        files: MapSet.new()
      },
      annotation_color: "blue",
      annotations: [],
      board_shapes: [],
      participants: %{},
      participant_id: participant_id(),
      display_name: socket.assigns.session_name || DisplayName.generate(),
      joined_at: System.system_time(:second),
      chat_messages: [],
      chat_error: nil,
      chat_open: false,
      chat_unread: 0,
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
      import_skips: [],
      # What a PGN import keeps; engine annotations are opt-in.
      import_keep: %{comments: true, variations: true, metadata: true, annotations: false},
      # The provider tray: metadata rows to select from, and the selection.
      import_games: [],
      import_selected: MapSet.new(),
      provider_username: "",
      chesscom_month: Calendar.strftime(Date.utc_today(), "%Y-%m"),
      chesscom_archives: [],
      chesscom_month_fallback: false,
      search_filters: %{
        "player" => "",
        "color" => "either",
        "result" => "either",
        "eco" => "",
        "opening" => "",
        "event" => "",
        "rating_min" => "",
        "rating_max" => "",
        "date_from" => "",
        "date_to" => "",
        "position_mode" => "similar",
        "fen" => "",
        "move_line" => "",
        "material_substitution" => "",
        "substitutions" => ""
      },
      search_corpus_size: nil,
      search_results: [],
      search_counts: nil,
      provider: nil,
      engine_on: false,
      engine_preview: nil,
      engine_error: nil,
      engine_peek: nil,
      engine_evals: %{},
      engine_pv_cache: %{},
      engine_cached: nil,
      engine_review: nil,
      engine_settings_open: false,
      features: nil,
      features_status: nil,
      features_detail: nil,
      engine_settings: %{depth: 20, multipv: 3}
    }

    case Rooms.get(code) do
      {:ok, room} ->
        if private_gate?(room, code, socket) do
          # A private room never reveals content to non-members: no presence,
          # no chat, no analyses, no subscription — only the gate card.
          {:ok, gate_socket(socket, base_assigns, code)}
        else
          chat_messages = room_chat(code)

          socket =
            socket
            |> assign(base_assigns)
            |> assign(room: room, analyses: AnalysisView.room_analyses(room, locale))
            |> assign_tracked()
            |> assign(chat_messages: chat_messages)
            |> stream(:chat_messages, chat_messages)
            |> allow_upload(:pgn,
              accept: ~w(.pgn .txt),
              max_entries: 1,
              max_file_size: 100_000,
              auto_upload: true
            )

          {:ok, subscribe_room(socket)}
        end

      :not_found ->
        {:ok,
         assign(socket, Map.put(base_assigns, :error, Web.I18n.t("home.joinNotFound", locale)))}
    end
  end

  # The room code alone never grants entry to a private room; only the owner
  # and rows in room_members pass. Guests are never members.
  defp private_gate?(%{owner_user_id: nil}, _code, _socket), do: false

  defp private_gate?(%{owner_user_id: owner_user_id}, code, socket)
       when is_binary(owner_user_id) do
    user_id = socket.assigns.current_user && socket.assigns.current_user.id
    not Rooms.member?(code, user_id)
  end

  defp gate_socket(socket, base_assigns, code) do
    assign(
      socket,
      Map.merge(base_assigns, %{
        room: nil,
        room_code: nil,
        private_gate: code
      })
    )
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

    path = if is_binary(params["p"]), do: parse_path(params["p"]), else: []

    # A debounced patch that matches the loaded state must not re-fetch and
    # re-render the whole analysis.
    already_loaded? =
      selected_id == socket.assigns.selected_analysis_id and
        not is_nil(socket.assigns.analysis) and
        path == socket.assigns.current_path

    socket =
      socket
      |> subscribe_analysis(selected_id)
      |> assign(url_analysis_id: requested_id, url_path: params["p"])
      |> assign(:selected_analysis_id, selected_id)
      |> then(fn s ->
        if already_loaded?, do: s, else: maybe_load_analysis(s, selected_id, path)
      end)
      |> refresh_presence()

    if selected_id && requested_id != selected_id do
      {:noreply,
       push_patch(socket,
         to: analysis_url(socket.assigns.room_code, selected_id, socket.assigns.current_path),
         replace: true
       )}
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

    {:noreply,
     assign(socket,
       theme: theme,
       piece_set: piece_set,
       annotation_color: annotation_color
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
    {:noreply, assign(socket, ui_modal: nil, share_pending_id: nil, engine_settings_open: false)}
  end

  def handle_event("open-library", _params, socket), do: Web.ShellPanels.open_library(socket)
  def handle_event("open-account", _params, socket), do: Web.ShellPanels.open_account(socket)

  def handle_event("account-delete-change", params, socket),
    do: Web.ShellPanels.account_delete_change(params, socket)

  def handle_event("unlink-provider", %{"provider" => provider}, socket),
    do: Web.ShellPanels.unlink_provider(socket, provider)

  def handle_event("toggle-lichess-sync", _params, socket),
    do: Web.ShellPanels.toggle_lichess_sync(socket)

  def handle_event("open-members", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("open-members", _params, socket) do
    if room_owner?(socket) do
      code = socket.assigns.room_code

      {:noreply,
       assign(socket,
         ui_modal: "members",
         members: Rooms.members(code),
         invite_editor_active: Rooms.invite_active?(code, :editor),
         invite_viewer_active: Rooms.invite_active?(code, :viewer),
         invite_token: nil,
         invite_url: nil,
         invite_token_role: nil
       )}
    else
      {:noreply, socket}
    end
  end

  # Only the room's owner may remove members; the credential is refreshed
  # before each event, the owner's own membership is immutable, and forged
  # targets that are not members change nothing.
  def handle_event("remove-member", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("remove-member", %{"user_id" => target}, socket) do
    if room_owner?(socket) do
      case Rooms.remove_member(socket.assigns.room_code, socket.assigns.current_user.id, target) do
        :ok ->
          {:noreply,
           socket
           |> assign(members: Rooms.members(socket.assigns.room_code))
           |> notify(Web.I18n.t("room.memberRemoved", socket.assigns.locale))}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Only the room's owner may change member roles; forged events from
  # non-owners change nothing, and the owner's own role is immutable.
  def handle_event("set-member-role", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("set-member-role", %{"user_id" => target, "role" => role}, socket) do
    if room_owner?(socket) and role in ["editor", "viewer"] do
      case Rooms.set_member_role(
             socket.assigns.room_code,
             socket.assigns.current_user.id,
             target,
             String.to_existing_atom(role)
           ) do
        :ok ->
          {:noreply,
           socket
           |> assign(members: Rooms.members(socket.assigns.room_code))
           |> notify(Web.I18n.t("room.memberRoleChanged", socket.assigns.locale))}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("generate-invite", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("generate-invite", %{"role" => role}, socket) do
    if room_owner?(socket) and role in ["editor", "viewer"] do
      code = socket.assigns.room_code
      # Rotation: creating a link invalidates the earlier one of that role.
      {:ok, token} = Rooms.create_invite(code, String.to_existing_atom(role))

      {:noreply,
       assign(socket,
         invite_token: token,
         invite_url: invite_url(socket, token),
         invite_token_role: role,
         invite_editor_active: Rooms.invite_active?(code, :editor),
         invite_viewer_active: Rooms.invite_active?(code, :viewer)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("revoke-invite", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("revoke-invite", %{"role" => role}, socket) do
    if room_owner?(socket) and role in ["editor", "viewer"] do
      code = socket.assigns.room_code
      _ = Rooms.revoke_invites(code, String.to_existing_atom(role))

      {:noreply,
       socket
       |> assign(
         invite_editor_active: Rooms.invite_active?(code, :editor),
         invite_viewer_active: Rooms.invite_active?(code, :viewer),
         invite_token: nil,
         invite_url: nil,
         invite_token_role: nil
       )
       |> notify(Web.I18n.t("room.inviteRevoked", socket.assigns.locale))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("copy-invite-link", _params, socket) do
    if url = socket.assigns.invite_url do
      {:noreply,
       push_event(socket, "copy-text", %{
         text: url,
         notice: Web.I18n.t("common.copied", socket.assigns.locale)
       })}
    else
      {:noreply, socket}
    end
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
       import_skips: [],
       import_games: [],
       import_selected: MapSet.new(),
       provider: nil
     )}
  end

  def handle_event("set-import-source", %{"source" => source}, socket)
      when source in ["paste", "library", "lichess", "chesscom"] do
    socket =
      assign(socket,
        import_source: source,
        provider: source,
        import_games: [],
        import_selected: MapSet.new(),
        import_error: nil
      )

    socket = if source == "lichess", do: prefill_lichess_username(socket), else: socket
    if source == "library", do: Web.ShellPanels.load_library(socket), else: {:noreply, socket}
  end

  # The three ways a library entry enters this room: only the underlying game,
  # an independent snapshot copy, or the live analysis itself. The credential
  # is refreshed before each event; parameters never select the owner or entry.
  def handle_event("library-add-game", %{"id" => _id}, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-add-game", %{"id" => id}, socket),
    do: add_game_from_library(socket, id)

  def handle_event("library-add-copy", %{"id" => _id}, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-add-copy", %{"id" => id}, socket),
    do: add_copy_from_library(socket, id)

  # "Share live" attaches the very analysis the library tracks — room edits
  # land in the owner's library — so it first asks for confirmation and
  # offers the two copy routes as alternatives.
  def handle_event("library-share", %{"id" => _id}, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-share", %{"id" => id}, socket) do
    has_game =
      Enum.any?(socket.assigns.library_entries || [], fn entry ->
        entry.id == id and not is_nil(entry.game_record_id)
      end)

    {:noreply,
     assign(socket,
       ui_modal: "share-confirm",
       share_pending_id: id,
       share_pending_has_game: has_game
     )}
  end

  def handle_event("library-share-confirm", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-share-confirm", _params, socket),
    do: share_pending(socket, &share_from_library/2)

  def handle_event("library-share-copy", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-share-copy", _params, socket),
    do: share_pending(socket, &add_copy_from_library/2)

  def handle_event("library-share-game", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("library-share-game", _params, socket),
    do: share_pending(socket, &add_game_from_library/2)

  # Rename, removal and paging inside the My Library tab stay shared
  # with the shell panel logic. This generic head deliberately sits after
  # the specific library-add actions above.
  def handle_event("library-" <> event, params, socket),
    do: Web.ShellPanels.handle_library_event(event, params, socket)

  def handle_event("open-search", _params, socket) do
    {:noreply,
     assign(socket,
       ui_modal: "search",
       search_results: [],
       search_counts: nil,
       search_cursor: nil,
       search_error: nil,
       search_filters: %{
         "player" => "",
         "color" => "either",
         "result" => "either",
         "eco" => "",
         "opening" => "",
         "event" => "",
         "rating_min" => "",
         "rating_max" => "",
         "date_from" => "",
         "date_to" => "",
         "position_mode" => "similar",
         "fen" => "",
         "move_line" => "",
         "material_substitution" => ""
       },
       search_corpus_size: GameSearch.corpus_size()
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

  def handle_event("track-analysis", %{"id" => _id}, %{assigns: %{current_user: nil}} = socket) do
    # Stars are not rendered for guests; forged events fail closed.
    {:noreply, socket}
  end

  def handle_event("track-analysis", %{"id" => id}, socket) do
    # Authentication is refreshed before each event. Never accept the owner,
    # room or analysis from event parameters; the id must be in this room.
    if analysis_in_room?(socket, id) do
      # Optimistic star: filled immediately, reverted on failure.
      socket = assign(socket, :tracked_ids, [id | List.delete(socket.assigns.tracked_ids, id)])

      case UserLibrary.track_from_room(
             socket.assigns.current_user.id,
             socket.assigns.room_code,
             id
           ) do
        {:ok, _state} ->
          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:tracked_ids, List.delete(socket.assigns.tracked_ids, id))
           |> notify(Web.I18n.t("room.trackFailed", socket.assigns.locale), :error)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("untrack-analysis", %{"id" => _id}, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("untrack-analysis", %{"id" => id}, socket) do
    if analysis_in_room?(socket, id) do
      # Optimistic: the star empties immediately; removal is idempotent and
      # only ever removes the reference, never the analysis or room content.
      socket = assign(socket, :tracked_ids, List.delete(socket.assigns.tracked_ids, id))
      _ = UserLibrary.remove(socket.assigns.current_user.id, id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-analysis", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.analyses, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(:current_path, [])
       |> push_patch(to: analysis_url(socket.assigns.room_code, id))}
    else
      {:noreply,
       notify(
         socket,
         Web.I18n.t("room.analysisLoadFailed", socket.assigns.locale, %{message: "not found"}),
         :error
       )}
    end
  end

  def handle_event(
        "follow-viewer",
        %{"analysis_id" => id, "path" => path, "participant_id" => participant_id},
        socket
      ) do
    if Enum.any?(socket.assigns.analyses, &(&1.id == id)) do
      path = parse_path(path)

      socket =
        if id == socket.assigns.selected_analysis_id do
          select_path(socket, path)
        else
          push_patch(socket, to: analysis_url(socket.assigns.room_code, id, path))
        end

      # The jump is invisible when already sitting on the followed position,
      # so always report what happened. The name comes from presence, never
      # from event parameters.
      {:noreply, follow_notice(socket, participant_id)}
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

  # Removing an analysis from the room asks first; the aggregate survives
  # while other rooms or library entries reference it (Rooms semantics).
  def handle_event("request-remove-analysis", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.analyses, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      analysis ->
        {:noreply, assign(socket, ui_modal: "remove-analysis", removal_pending: analysis)}
    end
  end

  def handle_event("remove-analysis", _params, socket) do
    case socket.assigns.removal_pending do
      nil ->
        {:noreply, assign(socket, :ui_modal, nil)}

      analysis ->
        case Rooms.remove_analysis(socket.assigns.room_code, analysis.id) do
          :ok ->
            socket =
              socket
              |> assign(ui_modal: nil, removal_pending: nil)
              |> refresh_room()
              |> notify(Web.I18n.t("room.removedAnalysis", socket.assigns.locale))

            if socket.assigns.selected_analysis_id == analysis.id do
              case socket.assigns.analyses do
                [first | _] ->
                  {:noreply,
                   push_patch(socket, to: analysis_url(socket.assigns.room_code, first.id))}

                [] ->
                  {:noreply, push_patch(socket, to: "/rooms/#{socket.assigns.room_code}")}
              end
            else
              {:noreply, socket}
            end

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(ui_modal: nil, removal_pending: nil)
             |> notify(
               Web.I18n.t("room.removeAnalysisFailed", socket.assigns.locale),
               :error
             )}
        end
    end
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
       |> assign(:ui_modal, nil)
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

  # The chat drawer lives behind the room bar's chat button; opening it
  # clears the unread badge.
  def handle_event("open-chat", _params, socket) do
    # The chat-log container only exists while the drawer is open, so the
    # mount-time stream items never reached the client. Re-sync the stream
    # from the message list whenever the drawer opens.
    {:noreply,
     socket
     |> assign(chat_open: true, chat_unread: 0)
     |> stream(:chat_messages, socket.assigns.chat_messages, reset: true)}
  end

  def handle_event("close-chat", _params, socket),
    do: {:noreply, assign(socket, :chat_open, false)}

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

    socket =
      assign(socket,
        engine_on: on?,
        engine_preview: nil,
        engine_pv_cache: %{},
        engine_cached: nil,
        engine_error: nil,
        engine_peek: nil,
        engine_settings_open: false
      )

    # A shared evaluation from the durable cache fills the panel instantly and
    # covers the request without starting the local worker (the hook sees the
    # coverage and skips the compute). Shallower cached results still compute.
    socket =
      if on? do
        case cached_engine_eval(socket) do
          {:ok, cached} ->
            preview = engine_preview_from_cache(socket, cached)

            socket
            |> assign(
              engine_preview: preview,
              engine_cached: %{
                fen: preview.fen,
                depth: preview.depth,
                multipv: length(preview.pv)
              }
            )
            |> merge_cached_graph_evals()

          :miss ->
            socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :board_shapes, board_shapes(socket))}
  end

  def handle_event("open-engine-settings", _params, socket),
    do: {:noreply, assign(socket, :engine_settings_open, true)}

  def handle_event("close-engine-settings", _params, socket),
    do: {:noreply, assign(socket, :engine_settings_open, false)}

  def handle_event("update-engine-settings", params, socket) do
    settings =
      Enum.reduce(["depth", "multipv"], socket.assigns.engine_settings, fn key, acc ->
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

  # The local engine worker reports throttled UCI info lines. Stale results
  # (an older position or a switched-off engine) are dropped, and the engine
  # only ever sees the FEN of the position on the board.
  def handle_event("engine-update", params, %{assigns: %{engine_on: true}} = socket) do
    with %{"fen" => fen, "lines" => [_ | _] = lines} <- params,
         true <- fen == current_fen(socket),
         {:ok, preview, pv_cache} <- engine_preview(lines, params, socket) do
      # Deeper results for the same position keep an open peek; only a fresh
      # position invalidates it.
      peek_stale? =
        case socket.assigns.engine_preview do
          %{fen: old_fen} -> old_fen != fen
          _ -> false
        end

      socket =
        assign(socket,
          engine_preview: preview,
          engine_error: nil,
          engine_pv_cache: pv_cache
        )

      socket = if peek_stale?, do: assign(socket, :engine_peek, nil), else: socket
      socket = store_engine_eval(socket, preview, Node.position_id(socket.assigns.current_node))

      # The panel now shows a fresh evaluation of this position at this depth.
      socket =
        assign(socket, :engine_cached, %{
          fen: preview.fen,
          depth: preview.depth,
          multipv: length(preview.pv)
        })

      # A completed (bestmove) search persists the result for everyone.
      if params["final"] do
        persist_engine_eval(socket, preview, lines)
      end

      {:noreply, assign(socket, :board_shapes, board_shapes(socket))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("engine-update", _params, socket), do: {:noreply, socket}

  # Clicking a move in an engine line plays the line up to that move into the
  # analysis, the same as playing those moves on the board. The line is
  # anchored at the position it was computed for; stale lines do nothing.
  def handle_event("engine-play-pv", %{"line" => line, "ply" => ply}, socket) do
    with %{fen: fen, pv: pv} <- socket.assigns.engine_preview || %{},
         true <- socket.assigns.engine_on and fen == current_fen(socket),
         {ply, ""} when ply >= 0 <- Integer.parse(ply),
         %{moves: moves} <- Enum.find(pv, &(&1.multipv == engine_int(line))),
         {:ok, analysis, revision, path} <- play_uci_line(socket, moves, ply) do
      {:noreply, update_analysis(socket, analysis, revision, path)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Hovering a move peeks at the position after that move, rendered as a
  # small static board next to the lines.
  def handle_event("engine-peek", %{"line" => line, "ply" => ply}, socket) do
    with %{fen: fen, pv: pv} <- socket.assigns.engine_preview || %{},
         true <- fen == current_fen(socket),
         {ply, ""} when ply >= 0 <- Integer.parse(ply),
         %{moves: moves} <- Enum.find(pv, &(&1.multipv == engine_int(line))),
         {:ok, position, label} <- peek_position(socket.assigns.position, moves, ply) do
      {:noreply, assign(socket, engine_peek: %{position: position, label: label})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("engine-peek-clear", _params, socket),
    do: {:noreply, assign(socket, :engine_peek, nil)}

  # The comment editor lives in a dialog; the moves panel header only keeps
  # the button (with a marker when the current node carries a comment).
  def handle_event("open-comment-editor", _params, socket),
    do: {:noreply, assign(socket, :ui_modal, "comment")}

  def handle_event("clear-comment", _params, socket) do
    with id when is_binary(id) <- socket.assigns.selected_analysis_id,
         {:ok, analysis, revision} <-
           Analyses.set_comment(id, socket.assigns.current_path, "") do
      {:noreply,
       socket
       |> update_analysis(analysis, revision, socket.assigns.current_path)
       |> assign(:ui_modal, nil)
       |> notify(Web.I18n.t("room.removedComment", socket.assigns.locale))}
    else
      _ ->
        {:noreply,
         notify(socket, Web.I18n.t("room.commentFailed", socket.assigns.locale), :error)}
    end
  end

  # The readout's detail strip: clicking a row explains the feature and —
  # when the feature has squares — pins them on the board. Clicking again
  # closes the strip and unpins.
  def handle_event("feature-detail", %{"id" => id}, socket) when is_binary(id) do
    detail = if socket.assigns.features_detail == id, do: nil, else: id
    socket = assign(socket, :features_detail, detail)

    visualizable? =
      case socket.assigns.features && Map.get(socket.assigns.features.values, id) do
        nil -> false
        value -> feature_drawable?(value, Catalogue.fetch!(id).board, socket.assigns.position)
      end

    {:noreply, if(visualizable?, do: toggle_pin(socket, id), else: socket)}
  end

  # Plays a book or endgame move into the analysis, like playing it on the
  # board.
  def handle_event(event, %{"uci" => uci}, socket)
      when event in ["book-play-move", "endgame-play-move"] do
    with {:ok, move} <- UCI.parse_move(socket.assigns.position, uci),
         {:ok, analysis, revision, path} <-
           Analyses.play(
             socket.assigns.selected_analysis_id,
             socket.assigns.current_path,
             move
           ) do
      {:noreply, update_analysis(socket, analysis, revision, path)}
    else
      _ -> {:noreply, socket}
    end
  end

  # A review walks the mainline of the current analysis: the local worker
  # evaluates every position at a fixed depth, one at a time, and the results
  # classify big eval swings. The panel's data attributes drive the hook;
  # revision changes (tree edits) invalidate an in-flight review.
  def handle_event("engine-review-start", _params, socket) do
    case {socket.assigns.analysis, socket.assigns.mainline_length} do
      {%AnalysisModel{}, length} when length >= 1 ->
        # A fresh run clears the previous review's marks from the move list.
        move_list = AnalysisView.move_list_data(socket.assigns.analysis, socket.assigns.locale)

        :telemetry.execute([:openchesslab, :engine, :review_started], %{count: 1})

        {:noreply,
         assign(socket,
           engine_review: %{
             status: :running,
             revision: socket.assigns.analysis_revision,
             total: length,
             done: 0,
             current: 0,
             queue: Enum.to_list(1..length),
             evals: %{}
           },
           engine_peek: nil,
           move_entries: move_list.entries,
           move_rows: move_list.rows,
           move_focus_paths: move_list.focus_paths
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("engine-review-cancel", _params, socket),
    do: {:noreply, assign(socket, :engine_review, nil)}

  def handle_event("engine-review-result", params, socket) do
    with %{status: :running, current: current, revision: revision} = review <-
           socket.assigns.engine_review || %{},
         :ok <- check_review_revision(revision, socket.assigns.analysis_revision),
         {ply, ""} when ply == current <- Integer.parse(params["ply"] || ""),
         cp <- params["cp"],
         mate <- params["mate"],
         true <- is_integer(cp) or is_integer(mate) do
      # UCI scores are relative to the side to move; reviews and the graph
      # store them white-relative, like the interactive engine updates.
      side = review_side(socket.assigns.analysis, ply)
      {cp, mate} = review_score_to_white(cp, mate, side)

      review = put_in(review.evals[ply], %{cp: cp, mate: mate})

      :telemetry.execute([:openchesslab, :engine, :review_ply], %{count: 1})

      socket =
        case AnalysisModel.node_at(socket.assigns.analysis, List.duplicate(0, ply)) do
          %Analysis.Node{} = node ->
            # Review results are finished computations at the review depth;
            # they persist like interactive bestmove results.
            PositionEvals.put(Node.position_id(node), @engine_id, %{
              depth: @engine_review_depth,
              eval_cp: cp,
              mate: mate
            })

            store_engine_eval(socket, %{eval_cp: cp, mate_in: mate}, Node.position_id(node))

          _ ->
            socket
        end

      advance_review(socket, review)
    else
      # The tree changed mid-review; the marks would attach to the wrong
      # moves. Cancel honestly instead of stalling forever.
      :cancelled ->
        {:noreply,
         socket
         |> assign(:engine_review, nil)
         |> notify(Web.I18n.t("room.reviewCancelledEdit", socket.assigns.locale), :error)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("engine-error", _params, socket) do
    socket =
      assign(socket,
        engine_on: false,
        engine_preview: nil,
        engine_error: "room.engineError"
      )

    {:noreply, assign(socket, :board_shapes, board_shapes(socket))}
  end

  # The search runs against the real canonical corpus: position predicates go
  # through PositionQuery/GameSearch (PostgreSQL, keyset-paged), name filters
  # are case-insensitive substrings on the PGN metadata.
  def handle_event("search-games", params, socket) do
    # Unchecked feature chips submit nothing; the selection resets honestly.
    filters =
      socket.assigns.search_filters
      |> Map.merge(params)
      |> Map.put("features", Map.get(params, "features", []))

    run_corpus_search(socket, filters)
  end

  def handle_event("set-position-mode", %{"mode" => mode}, socket) do
    run_corpus_search(
      socket,
      Map.put(socket.assigns.search_filters, "position_mode", mode)
    )
  end

  def handle_event("search-more", _params, socket) do
    case socket.assigns.search_cursor do
      nil ->
        {:noreply, socket}

      cursor ->
        case corpus_search(socket.assigns.search_filters, cursor) do
          {:ok, results, next} ->
            known = MapSet.new(Enum.map(socket.assigns.search_results, & &1.id))
            fresh = Enum.reject(results, &MapSet.member?(known, &1.id))

            {:noreply,
             assign(socket,
               search_results: socket.assigns.search_results ++ fresh,
               search_cursor: next
             )}

          {:error, _reason} ->
            {:noreply, socket}
        end
    end
  end

  # Opens a corpus hit as a fresh room analysis, like branching a library
  # game. The hit's ply becomes the landing path: a FEN hit opens on the
  # matched position itself, not on the game's start.
  def handle_event("open-corpus-game", %{"id" => record_id} = params, socket) do
    new_id = new_analysis_id()
    path = List.duplicate(0, parse_ply(params["ply"]))

    with {:ok, _analysis, _revision} <- Analyses.create_from_game_record(new_id, record_id),
         :ok <- Rooms.add_analysis(socket.assigns.room_code, new_id) do
      added(socket, new_id, "room.libraryAdded", path)
    else
      _ ->
        {:noreply,
         notify(
           socket,
           Web.I18n.t("room.searchOpenFailed", socket.assigns.locale, %{message: record_id}),
           :error
         )}
    end
  end

  def handle_event("search-use-board-fen", _params, socket) do
    fen = if socket.assigns.position, do: to_fen(socket.assigns.position), else: ""

    filters =
      socket.assigns.search_filters
      |> Map.put("fen", fen)
      |> Map.put("position_mode", "similar")

    {:noreply, assign(socket, :search_filters, filters)}
  end

  # Loads the provider's metadata rows into the tray. The games themselves
  # arrive later: Lichess rows are fetched by id on import, Chess.com rows
  # already carry their month's PGNs.
  def handle_event(
        "load-provider-games",
        %{"provider" => provider, "username" => username} = params,
        socket
      )
      when provider in ["lichess", "chesscom"] do
    username = String.trim(username)
    locale = socket.assigns.locale

    result =
      cond do
        username == "" ->
          {:error, :user_required}

        provider == "lichess" ->
          case GameImport.fetch_lichess_recent_games(username, @provider_recent_games) do
            {:ok, []} -> {:error, :no_games}
            other -> other
          end

        true ->
          # An invalid typed month is an honest error before any network
          # call; no month at all means the archives pick the newest one.
          case typed_month(params["month"]) do
            :error ->
              {:error, :bad_month}

            typed ->
              # The archives list replaces typing a month: pick from the
              # months that actually have games. The username prefetch may
              # already have fetched them; any failure falls back to the
              # plain month input.
              archives_result =
                case socket.assigns.chesscom_archives do
                  [_ | _] = archives -> {:ok, archives}
                  [] -> GameImport.fetch_chesscom_archives(username)
                end

              case archives_result do
                {:ok, [_ | _] = archives} ->
                  with {:ok, year, month} <- chesscom_month_choice(params["month"], archives) do
                    case GameImport.fetch_chesscom_month_games(username, year, month) do
                      {:ok, rows} ->
                        {:ok, rows, archives, format_chesscom_month(year, month)}

                      {:error, reason} ->
                        {:error, reason}
                    end
                  end

                _archives_unavailable ->
                  case typed do
                    {:ok, year, month} ->
                      case GameImport.fetch_chesscom_month_games(username, year, month) do
                        {:ok, rows} -> {:ok, rows, [], format_chesscom_month(year, month)}
                        {:error, reason} -> {:error, reason}
                      end

                    :none ->
                      {:error, :archives_unavailable}
                  end
              end
          end
      end

    case result do
      {:ok, rows, archives, month} ->
        {:noreply,
         assign(socket,
           import_games: rows,
           import_selected: MapSet.new(),
           provider_username: username,
           chesscom_archives: archives,
           chesscom_month: month,
           chesscom_month_fallback: archives == [],
           import_error: nil
         )}

      {:ok, rows} ->
        {:noreply,
         assign(socket,
           import_games: rows,
           import_selected: MapSet.new(),
           provider_username: username,
           chesscom_archives: [],
           chesscom_month: params["month"] || socket.assigns.chesscom_month,
           import_error: nil
         )}

      {:error, :user_required} ->
        {:noreply,
         assign(socket,
           import_error: Web.I18n.t("room.importUserRequired", locale),
           import_games: [],
           import_selected: MapSet.new()
         )}

      {:error, :bad_month} ->
        {:noreply,
         assign(socket,
           import_error: Web.I18n.t("room.importBadMonth", locale),
           import_games: [],
           import_selected: MapSet.new()
         )}

      {:error, :archives_unavailable} ->
        # Without archives or a typed month there is nothing to load: show
        # the plain month input with an honest explanation.
        {:noreply,
         assign(socket,
           import_error: Web.I18n.t("room.importArchivesUnavailable", locale),
           chesscom_month_fallback: true,
           import_games: [],
           import_selected: MapSet.new()
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           import_error: provider_error(reason, locale),
           import_games: [],
           import_selected: MapSet.new()
         )}
    end
  end

  def handle_event("prefetch-chesscom-month", %{"username" => username}, socket) do
    username = String.trim(username)

    if username == "" or socket.assigns.import_source != "chesscom" do
      {:noreply, assign(socket, chesscom_archives: [], chesscom_month_fallback: false)}
    else
      case GameImport.fetch_chesscom_archives(username) do
        {:ok, [_ | _] = archives} ->
          # The dropdown appears as soon as the username is known; the
          # newest month wins unless the current one is among the archives.
          month =
            case chesscom_month_choice(socket.assigns.chesscom_month, archives) do
              {:ok, year, month} -> format_chesscom_month(year, month)
            end

          {:noreply,
           assign(socket,
             chesscom_archives: archives,
             chesscom_month: month,
             chesscom_month_fallback: false
           )}

        {:error, _reason} ->
          {:noreply, assign(socket, chesscom_archives: [])}
      end
    end
  end

  def handle_event("toggle-import-all", _params, socket) do
    all_selected? =
      MapSet.size(socket.assigns.import_selected) == length(socket.assigns.import_games)

    if all_selected? do
      handle_event("select-no-import-games", %{}, socket)
    else
      handle_event("select-all-import-games", %{}, socket)
    end
  end

  def handle_event("select-chesscom-month", %{"month" => month}, socket) do
    # Choosing a month in the archives dropdown loads it right away.
    handle_event(
      "load-provider-games",
      %{
        "provider" => "chesscom",
        "username" => socket.assigns.provider_username,
        "month" => month
      },
      socket
    )
  end

  def handle_event("toggle-import-game", %{"id" => id}, socket) do
    selected = socket.assigns.import_selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, import_selected: selected)}
  end

  def handle_event("select-all-import-games", _params, socket) do
    selected = MapSet.new(Enum.map(socket.assigns.import_games, & &1.id))
    {:noreply, assign(socket, import_selected: selected)}
  end

  def handle_event("select-no-import-games", _params, socket),
    do: {:noreply, assign(socket, import_selected: MapSet.new())}

  def handle_event("import-selected-games", _params, socket) do
    selected = socket.assigns.import_selected
    rows = Enum.filter(socket.assigns.import_games, &MapSet.member?(selected, &1.id))
    locale = socket.assigns.locale

    cond do
      rows == [] ->
        {:noreply, socket}

      socket.assigns.import_source == "lichess" ->
        ids = Enum.map(rows, & &1.id)

        case GameImport.fetch_lichess_games_by_ids(ids) do
          {:ok, pgn, found} ->
            skips = for id <- ids -- found, do: skip("lichess.org/#{id}", :not_found, locale)
            import_text(socket, pgn, skips, "lichess")

          {:error, reason} ->
            {:noreply, assign(socket, import_error: provider_error(reason, locale))}
        end

      true ->
        # Chess.com rows already carry their PGN — no refetch.
        pgn = rows |> Enum.map(& &1.pgn) |> Enum.join("\n\n")
        import_text(socket, pgn, [], "chesscom")
    end
  end

  def handle_event("toggle-import-keep", %{"key" => key}, socket)
      when key in ~w(comments variations metadata annotations) do
    keep = Map.update!(socket.assigns.import_keep, String.to_existing_atom(key), &not/1)
    {:noreply, assign(socket, import_keep: keep)}
  end

  def handle_event("toggle-import-keep", _params, socket), do: {:noreply, socket}

  def handle_event("use-sample-pgn", _params, socket) do
    sample = DemoData.game("demo-ruy-lopez").pgn
    {:noreply, assign(socket, pgn: sample, import_error: nil)}
  end

  def handle_event("validate-pgn-upload", %{"pgn_text" => pgn}, socket),
    do: {:noreply, assign(socket, :pgn, pgn)}

  def handle_event("validate-pgn-upload", _params, socket), do: {:noreply, socket}

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
    {:noreply,
     assign(
       socket,
       :search_filters,
       Map.merge(socket.assigns.search_filters, Map.put_new(params, "features", []))
     )}
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
    url =
      analysis_url(
        socket.assigns.room_code,
        socket.assigns.selected_analysis_id,
        socket.assigns.current_path
      )

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

  # The linked account's username fills the tray's field — "my games" is the
  # same selection tray as everyone else's. A rejected token deletes the
  # grant honestly.
  defp prefill_lichess_username(socket) do
    case socket.assigns.current_user do
      %{id: user_id} ->
        with {:ok, token} <- ProviderGrants.get_token(user_id, "lichess"),
             {:ok, username} <- GameImport.fetch_lichess_account_username(token) do
          assign(socket, provider_username: username)
        else
          {:error, :unauthorized} ->
            :ok = ProviderGrants.delete(user_id, "lichess")

            assign(socket,
              import_error: Web.I18n.t("room.provider.unauthorized", socket.assigns.locale)
            )

          _ ->
            socket
        end

      _ ->
        socket
    end
  end

  @impl true
  def handle_info(:sync_position_url, socket) do
    {:noreply, sync_position_url(socket)}
  end

  # A membership change rechecks this view's own member: a removed member is
  # cut off immediately, before any further room content reaches them.
  def handle_info({:membership_changed, _room_code}, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    if is_map(room) and is_binary(room.owner_user_id) and is_map(user) and
         not Rooms.member?(room.id, user.id) do
      {:noreply,
       socket
       |> put_flash(:error, Web.I18n.t("room.memberRemovedKick", socket.assigns.locale))
       |> redirect(to: ~p"/rooms/#{room.id}")}
    else
      {:noreply, socket}
    end
  end

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
          # Our own writes echo back through the subscription — but the
          # revision we already hold IS the new one. Reloading would only
          # duplicate the work (a second async reference fetch per move,
          # superseding the first while its side effects already ran).
          if not is_nil(socket.assigns.analysis) and
               revision == socket.assigns.analysis_revision do
            {:noreply, socket}
          else
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

            {:noreply,
             socket
             |> set_analysis(analysis, revision, path)
             |> sync_position_url()}
          end

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
      # A visit counts as room activity for retention.
      :ok = Rooms.touch(code)
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
        socket = cancel_review_on_analysis_switch(socket, analysis.id)

        move_list =
          analysis
          |> AnalysisView.move_list_data(socket.assigns.locale)
          |> with_review_marks(socket.assigns.engine_review)

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
        |> refresh_engine_position()
        |> start_reference()
        |> maybe_load_features()
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
        socket
        |> assign(room: room, analyses: AnalysisView.room_analyses(room, socket.assigns.locale))
        |> assign_tracked()

      :not_found ->
        assign(socket, room: nil, error: Web.I18n.t("home.joinNotFound", socket.assigns.locale))
    end
  end

  # A star reflects this user's live library reference to a room analysis;
  # the list is refetched whenever the room's analysis set changes.
  defp assign_tracked(socket) do
    ids = Enum.map(socket.assigns.analyses, & &1.id)

    tracked =
      if user = socket.assigns.current_user,
        do: UserLibrary.tracked(user.id, ids),
        else: []

    assign(socket, :tracked_ids, tracked)
  end

  # Adding from the library closes the import dialog, refreshes the room,
  # selects the analysis and reports what happened.
  defp added(socket, analysis_id, message_key), do: added(socket, analysis_id, message_key, [])

  defp added(socket, analysis_id, message_key, path) do
    socket =
      socket
      |> assign(:ui_modal, nil)
      |> refresh_room()
      |> notify(Web.I18n.t(message_key, socket.assigns.locale))

    {:noreply,
     socket
     |> assign(:current_path, path)
     |> push_patch(to: analysis_url(socket.assigns.room_code, analysis_id, path))}
  end

  defp shared(socket, analysis_id), do: added(socket, analysis_id, "room.libraryShared")

  # Runs a library-add action against the entry the share-confirm modal is
  # pending on; each action re-authorizes against the refreshed credential.
  defp share_pending(socket, action) do
    case socket.assigns.share_pending_id do
      id when is_binary(id) -> action.(socket, id)
      _ -> {:noreply, assign(socket, ui_modal: nil, share_pending_id: nil)}
    end
  end

  defp add_game_from_library(socket, id) do
    with {:ok, new_id} <-
           UserLibrary.branch_game(socket.assigns.current_user.id, id),
         :ok <- Rooms.add_analysis(socket.assigns.room_code, new_id) do
      added(socket, new_id, "room.libraryAdded")
    else
      {:error, _reason} -> library_add_failed(socket)
    end
  end

  defp add_copy_from_library(socket, id) do
    with {:ok, new_id} <-
           UserLibrary.branch_analysis(socket.assigns.current_user.id, id),
         :ok <- Rooms.add_analysis(socket.assigns.room_code, new_id) do
      added(socket, new_id, "room.libraryAdded")
    else
      {:error, _reason} -> library_add_failed(socket)
    end
  end

  defp share_from_library(socket, id) do
    with :ok <- UserLibrary.authorize_share(socket.assigns.current_user.id, id),
         :ok <- Rooms.add_analysis(socket.assigns.room_code, id) do
      shared(socket, id)
    else
      {:error, _reason} -> library_add_failed(socket)
    end
  end

  defp library_add_failed(socket) do
    {:noreply, notify(socket, Web.I18n.t("room.libraryAddFailed", socket.assigns.locale), :error)}
  end

  defp analysis_in_room?(socket, id),
    do: Enum.any?(socket.assigns.analyses, &(&1.id == id))

  defp room_owner?(socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user
    is_map(room) and is_map(user) and room.owner_user_id == user.id
  end

  # The connected request's own host keeps the link correct in development
  # and behind the production domain.
  defp invite_url(socket, token) do
    path = ~p"/rooms/#{socket.assigns.room_code}/join/#{token}"
    URI.to_string(%{socket.host_uri | path: path})
  end

  defp follow_notice(socket, participant_id) do
    case Map.get(socket.assigns.participants, participant_id) do
      %{display_name: name} when is_binary(name) and name != "" ->
        notify(socket, Web.I18n.t("room.followedViewer", socket.assigns.locale, %{name: name}))

      _other ->
        socket
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
    # Any analysis change counts as room activity for retention.
    :ok = Rooms.touch(socket.assigns.room_code)

    socket
    |> refresh_room()
    |> assign(:selected_analysis_id, analysis.id)
    |> assign(:engine_peek, nil)
    |> set_analysis(analysis, revision, path)
    |> sync_position_url()
  end

  # Navigation renders instantly and syncs the URL with a trailing debounce:
  # a push_patch per keypress keeps a pending link open, which buffers every
  # render diff until the burst ends (the screen freezes while the URL moves).
  # The timer is idempotent: sync_position_url no-ops when the URL matches.
  defp select_path(socket, path) do
    case socket.assigns.analysis do
      %AnalysisModel{} = analysis ->
        if AnalysisModel.node_at(analysis, path) do
          Process.send_after(self(), :sync_position_url, @url_sync_debounce_ms)

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

  # Replace the current history entry rather than adding one entry per move.
  # handle_params/3 owns URL parsing; do not call this from handle_params/3.
  defp sync_position_url(%{assigns: %{selected_analysis_id: nil}} = socket), do: socket

  defp sync_position_url(socket) do
    path =
      case socket.assigns.current_path do
        [] -> nil
        steps -> Enum.join(steps, ",")
      end

    if socket.assigns.url_analysis_id == socket.assigns.selected_analysis_id and
         socket.assigns.url_path == path do
      socket
    else
      push_patch(socket,
        to:
          analysis_url(
            socket.assigns.room_code,
            socket.assigns.selected_analysis_id,
            socket.assigns.current_path
          ),
        replace: true
      )
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

  # Imports whatever the box holds: PGN (possibly several games) and Lichess
  # game URLs. Whatever parses is imported into the room; every failure is
  # listed as a skip — only a total failure is an error.
  defp import_pgn(socket, text) when is_binary(text) do
    locale = socket.assigns.locale
    %{lichess_ids: ids, chesscom_urls: chesscom_urls, pgn: pgn} = GameImport.split_input(text)

    {lichess_pgn, skips} =
      case ids do
        [] ->
          {nil, []}

        ids ->
          case GameImport.fetch_lichess_games_by_ids(ids) do
            {:ok, fetched, found} ->
              {fetched,
               for(id <- ids -- found, do: skip("lichess.org/#{id}", :not_found, locale))}

            {:error, reason} ->
              {nil, for(id <- ids, do: skip("lichess.org/#{id}", reason, locale))}
          end
      end

    skips = skips ++ for(url <- chesscom_urls, do: skip(url, :chesscom_url, locale))

    # Each part splits on its own: a headerless pasted game next to a
    # headered fetch is a valid mix.
    chunks =
      [pgn, lichess_pgn]
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(&split_part/1)

    import_chunks(socket, chunks, skips, "pgn")
  end

  # Imports every game chunk into the room. The dialog stays open when
  # anything was skipped so the list is visible.
  defp import_text(socket, text, skips, source) do
    import_chunks(socket, split_part(text), skips, source)
  end

  defp split_part(part) do
    case PgnBatchImporter.split_games(part) do
      {:ok, chunks} -> chunks
      # A part that does not split cleanly is imported as-is and fails (or
      # not) in the importer, where it becomes an honest skip.
      {:error, _} -> [part]
    end
  end

  defp import_chunks(socket, chunks, skips, source) do
    locale = socket.assigns.locale

    {analyses, skips} =
      run_imports(chunks, skips, [source: source] ++ keep_opts(socket.assigns.import_keep))

    {added, skips} = add_to_room(socket, analyses, skips, locale)

    case added do
      [] ->
        {:noreply,
         assign(socket,
           import_error: Web.I18n.t("room.importNothingImported", locale),
           import_skips: skips
         )}

      [first | _] ->
        socket = refresh_room(socket)

        socket =
          socket
          |> assign(import_error: nil, import_skips: skips, current_path: [])
          |> push_patch(to: analysis_url(socket.assigns.room_code, first.id))
          |> notify(import_notice(length(added), skips, locale))

        if skips == [] do
          {:noreply, assign(socket, ui_modal: nil)}
        else
          {:noreply, assign(socket, ui_modal: "import")}
        end
    end
  end

  defp keep_opts(%{
         comments: comments,
         variations: variations,
         metadata: metadata,
         annotations: annotations
       }) do
    [
      keep_comments: comments,
      keep_variations: variations,
      keep_metadata: metadata,
      keep_annotations: annotations
    ]
  end

  defp run_imports(chunks, skips, opts) do
    chunks
    |> Enum.with_index(1)
    |> Enum.reduce({[], skips}, fn {chunk, index}, {analyses, skips} ->
      case PgnAnalysisImporter.import(new_analysis_id(), new_game_record_id(), chunk, opts) do
        {:ok, analysis, _revision} ->
          {[analysis | analyses], skips}

        {:error, {:invalid_pgn, message}} ->
          {analyses, skips ++ [%{source: "game #{index}", detail: message}]}

        {:error, reason} ->
          {analyses, skips ++ [%{source: "game #{index}", detail: inspect(reason)}]}
      end
    end)
    |> then(fn {analyses, skips} -> {Enum.reverse(analyses), skips} end)
  end

  defp add_to_room(socket, analyses, skips, locale) do
    Enum.reduce(analyses, {[], skips}, fn analysis, {added, skips} ->
      case Rooms.add_analysis(socket.assigns.room_code, analysis.id) do
        :ok -> {[analysis | added], skips}
        {:error, _} -> {added, skips ++ [skip(analysis.id, :room, locale)]}
      end
    end)
    |> then(fn {added, skips} -> {Enum.reverse(added), skips} end)
  end

  defp skip(source, reason, locale) do
    %{source: source, detail: Web.I18n.t("room.skip.#{reason}", locale)}
  end

  defp provider_error(reason, locale),
    do: Web.I18n.t("room.provider.#{reason}", locale)

  defp import_notice(count, [], _locale),
    do: Web.I18n.plural("room.importedCount", count, %{})

  defp import_notice(count, skips, locale),
    do: Web.I18n.t("room.importedWithSkips", locale, %{imported: count, skipped: length(skips)})

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
      |> bump_chat_unread(message)
      |> stream_insert(:chat_messages, message, at: -1, limit: -200)
    end
  end

  # A message from someone else while the drawer is closed raises the badge.
  defp bump_chat_unread(socket, message) do
    if not socket.assigns.chat_open and message.author_id != socket.assigns.participant_id do
      assign(socket, :chat_unread, socket.assigns.chat_unread + 1)
    else
      socket
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

    # The engine arrow sits under everyone's annotations.
    engine_best_move_shape(socket) ++ remote ++ socket.assigns.annotations
  end

  # A green arrow for the engine's top move, only while the preview matches
  # the position on the board.
  defp engine_best_move_shape(socket) do
    with %{fen: fen, pv: [%{moves: [%{uci: uci} | _]} | _]} <- socket.assigns.engine_preview,
         true <- socket.assigns.engine_on and fen == current_fen(socket),
         {:ok, move} <- UCI.parse_move(socket.assigns.position, uci) do
      [%{type: :arrow, from: move.from, to: move.to, color: "engine"}]
    else
      _ -> []
    end
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

  defp parse_month(<<year::binary-4, "-", month::binary-2>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         true <- year > 0 and month in 1..12 do
      {:ok, year, month}
    else
      _ -> :error
    end
  end

  defp parse_month(_), do: :error

  # The disabled placeholder select submits no month at all; only a typed
  # but invalid month is an error.
  defp typed_month(nil), do: :none
  defp typed_month(""), do: :none
  defp typed_month(month), do: parse_month(month)

  # Pick the typed month when the archives actually contain it, else the
  # newest archive.
  defp chesscom_month_choice(typed, archives) do
    case parse_month(typed || "") do
      {:ok, year, month} ->
        if {year, month} in archives,
          do: {:ok, year, month},
          else: newest_archive(archives)

      :error ->
        newest_archive(archives)
    end
  end

  defp newest_archive([{year, month} | _rest]), do: {:ok, year, month}

  defp format_chesscom_month(year, month) do
    "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}"
  end

  @doc false
  def chesscom_month_label({year, month}, locale) do
    "#{month_name(month, locale)} #{year}"
  end

  defp month_name(month, "nl") do
    Enum.at(
      ~w(januari februari maart april mei juni juli augustus september oktober november december),
      month - 1
    )
  end

  defp month_name(month, _locale) do
    Enum.at(
      ~w(January February March April May June July August September October November December),
      month - 1
    )
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

  defp analysis_url(code, nil, _path), do: analysis_url(code, nil)
  defp analysis_url(code, id, []), do: analysis_url(code, id)

  defp analysis_url(code, id, path) when is_list(path) do
    analysis_url(code, id) <> "&p=" <> URI.encode(Enum.join(path, ","))
  end

  defp room_topic(code), do: "room:#{code}"

  defp participant_id, do: "lv-" <> Base.encode16(:crypto.strong_rand_bytes(8))

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

  defdelegate initials(name), to: DisplayName

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
  defp shape_color("engine"), do: "#2fbf71"
  defp shape_color(_color), do: "#3b6fe0"

  defp engine_setting_bounds("depth"), do: {1, 40}
  defp engine_setting_bounds("multipv"), do: {1, 10}

  defp eval_white_share(%{mate_in: mate}) when is_integer(mate) and mate > 0, do: 100.0
  defp eval_white_share(%{mate_in: mate}) when is_integer(mate) and mate < 0, do: 0.0

  defp eval_white_share(%{eval_cp: cp}) when is_number(cp) do
    cp = max(-1000, min(1000, cp))
    Float.round((0.5 + cp / 2000) * 100, 1)
  end

  defp eval_white_share(_preview), do: 50.0

  defp eval_label(%{mate_in: mate}) when is_integer(mate) and mate > 0,
    do: "#" <> to_string(mate)

  defp eval_label(%{mate_in: mate}) when is_integer(mate) and mate < 0,
    do: "#-" <> to_string(abs(mate))

  defp eval_label(%{eval_cp: cp}) when is_number(cp) do
    score = :erlang.float_to_binary(abs(cp) / 100, decimals: 2)
    if cp >= 0, do: "+" <> score, else: "-" <> score
  end

  defp eval_label(_preview), do: "—"

  # Builds the engine panel state from throttled UCI info pushed by the local
  # worker. UCI scores are relative to the side to move; the panel and the
  # evaluation bar are white-relative, so scores flip when Black is to move.
  defp engine_preview(lines, params, socket) do
    position = socket.assigns.position
    flip = if position.side_to_move == :black, do: -1, else: 1
    context = AnalysisView.move_context(socket.assigns.analysis, socket.assigns.current_path)

    {pv, pv_cache} =
      lines
      |> Enum.sort_by(fn line -> engine_int(line["multipv"]) end)
      |> Enum.map_reduce(socket.assigns.engine_pv_cache, fn line, cache ->
        pv_key = line["pv"] || ""

        case Map.fetch(cache, pv_key) do
          # Parsing every move of every line against the legal-move rules is
          # the hot path; the pv string identifies the parsed result.
          {:ok, moves} ->
            {%{
               multipv: engine_int(line["multipv"]),
               score: score_label(line, flip),
               moves: moves
             }, cache}

          :error ->
            moves =
              pv_key
              |> String.split(" ", trim: true)
              |> Enum.zip(UCI.pv_to_san(position, pv_key))
              |> Enum.map(fn {uci, san} -> %{uci: uci, san: san} end)

            case moves do
              [] ->
                {nil, cache}

              _ ->
                moves = add_move_labels(moves, context)

                {%{
                   multipv: engine_int(line["multipv"]),
                   score: score_label(line, flip),
                   moves: moves
                 }, Map.put(cache, pv_key, moves)}
            end
        end
      end)

    pv = Enum.reject(pv, &is_nil/1)

    case pv do
      [] ->
        :error

      _ ->
        {eval_cp, mate_in} = white_relative_score(List.first(lines), flip)

        {:ok,
         %{
           fen: params["fen"],
           eval_cp: eval_cp,
           mate_in: mate_in,
           depth: engine_int(params["depth"]),
           nodes: engine_int(params["nodes"]),
           nps: engine_int(params["nps"]),
           pv: pv
         }, pv_cache}
    end
  end

  # Numbers the moves of an engine line the way the move list does: a number
  # on White's moves, and on Black's only when the line starts with one.
  defp add_move_labels(moves, %Analysis.MoveContext{} = context) do
    Enum.map(Enum.with_index(moves), fn {move, index} ->
      context = Analysis.MoveContext.at(context.fullmove_number, context.side, index)

      label =
        cond do
          context.side == :white -> "#{context.fullmove_number}."
          index == 0 -> "#{context.fullmove_number}..."
          true -> nil
        end

      number_label =
        if context.side == :white,
          do: "#{context.fullmove_number}.",
          else: "#{context.fullmove_number}..."

      move
      |> Map.put(:label, label)
      |> Map.put(:number_label, number_label)
    end)
  end

  defp add_move_labels(moves, _context), do: moves

  defp white_relative_score(line, flip) do
    cond do
      mate = line["score_mate"] -> {nil, engine_int(mate) * flip}
      cp = line["score_cp"] -> {engine_int(cp) * flip, nil}
      true -> {nil, nil}
    end
  end

  defp score_label(line, flip) do
    cond do
      mate = line["score_mate"] ->
        n = engine_int(mate) * flip
        if n > 0, do: "#" <> to_string(n), else: "#-" <> to_string(abs(n))

      cp = line["score_cp"] ->
        cp = engine_int(cp) * flip
        score = :erlang.float_to_binary(abs(cp) / 100, decimals: 2)
        if cp >= 0, do: "+" <> score, else: "-" <> score

      true ->
        "—"
    end
  end

  # Plays the first ply + 1 moves of an engine line into the analysis at the
  # current path: the UCI coordinates resolve to legal moves up front, then a
  # single Analyses.play_line/3 persists the whole line in one transaction
  # (one revision bump, one broadcast — not one round trip per move).
  defp play_uci_line(socket, moves, ply) do
    with {:ok, resolved} <- resolve_uci_moves(socket.assigns.position, Enum.take(moves, ply + 1)),
         {:ok, analysis, revision, path} <-
           Analyses.play_line(
             socket.assigns.selected_analysis_id,
             socket.assigns.current_path,
             resolved
           ) do
      {:ok, analysis, revision, path}
    else
      _ -> :error
    end
  end

  defp resolve_uci_moves(position, moves) do
    moves
    |> Enum.reduce_while({:ok, position, []}, fn move, {:ok, current, acc} ->
      with {:ok, legal} <- UCI.parse_move(current, move.uci),
           {:ok, next} <- Position.apply_move(current, legal) do
        {:cont, {:ok, next, [legal | acc]}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, _position, resolved} -> {:ok, Enum.reverse(resolved)}
      :error -> :error
    end
  end

  # Applies the first ply + 1 moves of a line to the shown position and
  # returns the resulting board plus the clicked move's label.
  defp peek_position(position, moves, ply) do
    case Enum.fetch(moves, ply) do
      {:ok, clicked} ->
        position =
          moves
          |> Enum.take(ply + 1)
          |> Enum.reduce_while(position, fn move, current ->
            with {:ok, legal} <- UCI.parse_move(current, move.uci),
                 {:ok, next} <- Position.apply_move(current, legal) do
              {:cont, next}
            else
              _ -> {:halt, current}
            end
          end)

        {:ok, position, "#{clicked.number_label} #{clicked.san}"}

      :error ->
        :error
    end
  end

  # Every evaluated position feeds a small session store keyed by canonical
  # position id, which the evaluation graph renders. Nothing is persisted:
  # recomputing is cheap and the graph refills as you navigate with the engine
  # on. Position ids are stable across edits, and evals even follow
  # transpositions between lines.
  defp store_engine_eval(socket, preview, position_id) do
    label = eval_label(%{eval_cp: preview.eval_cp, mate_in: preview.mate_in})

    assign(
      socket,
      :engine_evals,
      Map.put(socket.assigns.engine_evals, position_id, %{
        cp: preview.eval_cp,
        mate: preview.mate_in,
        label: label
      })
    )
  end

  @eval_graph_max_cp 600

  # Data for the evaluation graph: one point per mainline ply with a session
  # eval, click columns for every ply, and the marker for the current path.
  # Review marks color the dot of the position a move landed on.
  defp eval_graph(evals, analysis, mainline_length, current_path, marks) do
    width = 300
    step = width / (mainline_length + 1)

    points =
      for ply <- 0..mainline_length,
          node = AnalysisModel.node_at(analysis, List.duplicate(0, ply)),
          not is_nil(node),
          eval = Map.get(evals, Node.position_id(node)),
          not is_nil(eval) do
        cp = graph_cp(eval)
        x = Float.round(step * (ply + 0.5), 1)
        y = Float.round(30 - cp / @eval_graph_max_cp * 26, 1)
        {ply, x, y, eval.label}
      end

    runs =
      points
      |> Enum.reduce([], fn point, acc ->
        {ply, _x, _y, _label} = point

        case acc do
          [[{last_ply, _, _, _} | _] = run | rest] when ply == last_ply + 1 ->
            [[point | run] | rest]

          _ ->
            [[point] | acc]
        end
      end)
      |> Enum.map(&Enum.reverse/1)

    groups =
      for run <- runs,
          length(run) > 1,
          do: Enum.map_join(run, " ", fn {_ply, x, y, _label} -> "#{x},#{y}" end)

    columns =
      for ply <- 0..mainline_length do
        %{
          x: Float.round(step * ply, 1),
          w: Float.round(step, 1),
          path: Enum.join(List.duplicate(0, ply), ",")
        }
      end

    current_ply = min(length(current_path), mainline_length)

    %{
      any: points != [],
      groups: groups,
      dots:
        Enum.map(points, fn {ply, x, y, label} ->
          %{
            x: x,
            y: y,
            label: label,
            color: review_dot_color(marks[ply - 1])
          }
        end),
      columns: columns,
      current_x: Float.round(step * (current_ply + 0.5), 1),
      height: 60
    }
  end

  defp review_dot_color(nil), do: "var(--foreground)"
  defp review_dot_color(%{mark: mark}) when mark in ["?", "??"], do: "var(--error)"
  defp review_dot_color(%{mark: "?!"}), do: "var(--warning)"

  defp graph_cp(%{mate: mate}) when is_integer(mate) and mate > 0, do: @eval_graph_max_cp
  defp graph_cp(%{mate: mate}) when is_integer(mate) and mate < 0, do: -@eval_graph_max_cp

  defp graph_cp(%{cp: cp}) when is_integer(cp),
    do: max(-@eval_graph_max_cp, min(@eval_graph_max_cp, cp))

  defp graph_cp(_eval), do: 0

  defp advance_review(socket, review) do
    case review.queue do
      [next | rest] ->
        {:noreply,
         assign(socket,
           engine_review: %{
             review
             | done: review.done + 1,
               current: next,
               queue: rest
           }
         )}

      [] ->
        classified = classify_review(socket.assigns.analysis, review)

        # Classification lands on the move list as well as the summary.
        move_list =
          socket.assigns.analysis
          |> AnalysisView.move_list_data(socket.assigns.locale)
          |> with_review_marks(classified)

        {:noreply,
         assign(socket,
           engine_review: classified,
           move_entries: move_list.entries,
           move_rows: move_list.rows,
           move_focus_paths: move_list.focus_paths
         )}
    end
  end

  # Classification follows lichess's published model: centipawns map to a win
  # probability with a logistic curve fitted to real games (scalachess
  # eval.scala, MIT; https://lichess.org/page/accuracy), and a move is marked
  # by how much it drops the mover's Win%: >30 points is a blunder, >20 a
  # mistake, >10 an inaccuracy. Unlike raw centipawn loss this is
  # position-independent — big cp swings in already-decided games barely move
  # Win%, so they no longer misclassify.
  defp classify_review(analysis, review) do
    marks =
      for ply <- 0..(review.total - 1),
          before_eval = review.evals[ply],
          after_eval = review.evals[ply + 1],
          before_eval != nil and after_eval != nil do
        side =
          case AnalysisView.move_context(analysis, List.duplicate(0, ply)) do
            %{side: side} -> side
            _ -> :white
          end

        win_before = win_percent(before_eval)
        win_after = win_percent(after_eval)
        drop = (win_before - win_after) * if(side == :white, do: 1, else: -1)

        mark =
          cond do
            drop > 30 -> "??"
            drop > 20 -> "?"
            drop > 10 -> "?!"
            true -> nil
          end

        mark &&
          {ply,
           %{
             mark: mark,
             loss: drop,
             win_before: Float.round(win_before, 1),
             win_after: Float.round(win_after, 1)
           }}
      end
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    Map.merge(review, %{
      status: :done,
      done: review.total + 1,
      marks: marks,
      accuracy: review_accuracy(analysis, review),
      counts: %{
        blunders: count_marks(marks, "??"),
        mistakes: count_marks(marks, "?"),
        inaccuracies: count_marks(marks, "?!")
      }
    })
  end

  defp count_marks(marks, mark) do
    marks |> Map.values() |> Enum.count(&(&1.mark == mark))
  end

  # Game accuracy per side from the reviewed eval series, following lichess's
  # published aggregation (see Web.Accuracy).
  defp review_accuracy(analysis, review) do
    wins = for ply <- 0..review.total, do: win_percent(review.evals[ply] || %{})

    start_side =
      case AnalysisView.move_context(analysis, []) do
        %{side: side} -> side
        _ -> :white
      end

    Accuracy.game(wins, start_side)
  end

  # The review summary's accuracy line: only sides that moved get a number.
  defp review_accuracy_text(accuracy, locale) do
    [white: accuracy.white, black: accuracy.black]
    |> Enum.filter(fn {_side, value} -> value != nil end)
    |> Enum.map_join(" · ", fn {side, value} -> "#{side_name(side, locale)} #{round(value)}%" end)
  end

  defp check_review_revision(revision, revision), do: :ok
  defp check_review_revision(_review_revision, _analysis_revision), do: :cancelled

  # A review belongs to the analysis it started on. Switching analyses
  # discards it — running or done — so the worker never keeps reviewing the
  # new game from the old ply, and the old game's marks never show on it.
  # Compare against the loaded analysis: handle_params rewrites
  # selected_analysis_id before loading.
  defp cancel_review_on_analysis_switch(socket, analysis_id) do
    case socket.assigns.analysis do
      %AnalysisModel{id: previous} when previous != analysis_id ->
        assign(socket, engine_review: nil)

      _ ->
        socket
    end
  end

  # A book move's W/D/L segment width as a share of its recorded results.
  defp book_share(count, move) do
    total = move.white + move.draws + move.black
    if total > 0, do: Float.round(count / total * 100, 1), else: 0.0
  end

  # The tablebase categories, grouped by outcome. Every category from the
  # API is named explicitly; unknown ones fall back to the unavailable text.
  @endgame_winning ["win", "syzygy-win"]
  @endgame_cursed ["cursed-win", "maybe-win"]
  @endgame_blessed ["blessed-loss", "maybe-loss"]
  @endgame_losing ["loss", "syzygy-loss"]

  # The headline names the outcome for the side to move, in colour terms.
  defp endgame_headline(result, position, locale) do
    color =
      if position.side_to_move == :white,
        do: Web.I18n.t("room.endgameWhite", locale),
        else: Web.I18n.t("room.endgameBlack", locale)

    cond do
      result["category"] in @endgame_winning ->
        Web.I18n.t("room.endgameWins", locale, %{color: color})

      result["category"] in @endgame_cursed ->
        Web.I18n.t("room.endgameCursedWin", locale, %{color: color})

      result["category"] == "draw" ->
        Web.I18n.t("room.endgameDraw", locale)

      result["category"] in @endgame_blessed ->
        Web.I18n.t("room.endgameBlessedLoss", locale, %{color: color})

      result["category"] in @endgame_losing ->
        Web.I18n.t("room.endgameLoses", locale, %{color: color})

      true ->
        Web.I18n.t("room.endgameNotAvailable", locale)
    end
  end

  # Mate distance when the tablebase knows it, else the DTZ — which counts to
  # the next zeroing move, not to mate, so it is labelled separately.
  defp endgame_distance(result, locale) do
    cond do
      is_integer(result["dtm"]) ->
        if result["category"] in @endgame_winning or result["category"] in @endgame_cursed do
          Web.I18n.t("room.endgameMateIn", locale, %{count: abs(result["dtm"])})
        else
          Web.I18n.t("room.endgameMatedIn", locale, %{count: abs(result["dtm"])})
        end

      is_integer(result["dtz"]) and result["dtz"] != 0 ->
        Web.I18n.t("room.endgameDtz", locale, %{count: abs(result["dtz"])})

      true ->
        nil
    end
  end

  # A move's category is from the perspective of the side that must move
  # after it; the chip shows the outcome for the player who plays the move.
  # A star marks outcomes that only hold without the 50-move rule.
  defp endgame_chip(category, locale) do
    cond do
      category in @endgame_losing -> Web.I18n.t("room.endgameMoveWin", locale)
      category in @endgame_cursed -> Web.I18n.t("room.endgameMoveLoss", locale) <> "*"
      category == "draw" -> Web.I18n.t("room.endgameMoveDraw", locale)
      category in @endgame_blessed -> Web.I18n.t("room.endgameMoveWin", locale) <> "*"
      category in @endgame_winning -> Web.I18n.t("room.endgameMoveLoss", locale)
      true -> "?"
    end
  end

  defp endgame_has_fifty?(result) do
    Enum.any?(result["moves"], fn move ->
      move["category"] in @endgame_cursed or move["category"] in @endgame_blessed
    end)
  end

  @review_clamp_cp 1000

  # Win% from a white-relative eval, the logistic curve lichess fits to real
  # games: 0cp ≈ 50%, +100 ≈ 59%, +400 ≈ 81%, mates saturate at 0/100.
  @win_percent_multiplier -0.00368208

  defp win_percent(%{mate: mate}) when is_integer(mate) and mate > 0, do: 100.0
  defp win_percent(%{mate: mate}) when is_integer(mate) and mate < 0, do: 0.0

  defp win_percent(%{cp: cp}) when is_integer(cp) do
    cp = max(-@review_clamp_cp, min(@review_clamp_cp, cp))
    50 + 50 * (2 / (1 + :math.exp(@win_percent_multiplier * cp)) - 1)
  end

  defp win_percent(_eval), do: 50.0

  defp review_side(analysis, ply) do
    case AnalysisView.move_context(analysis, List.duplicate(0, ply)) do
      %{side: side} -> side
      _ -> :white
    end
  end

  defp review_score_to_white(cp, mate, side) do
    flip = if side == :black, do: -1, else: 1

    cond do
      is_integer(mate) and mate != 0 -> {nil, mate * flip}
      # mate 0: the side to move is checkmated — a terminal position
      is_integer(mate) and side == :white -> {-@review_clamp_cp, nil}
      is_integer(mate) -> {@review_clamp_cp, nil}
      true -> {cp * flip, nil}
    end
  end

  # The FEN of the position the review is currently analyzing; empty when no
  # review is running, which returns the hook to interactive mode.
  defp review_fen(%{engine_review: %{status: :running, current: ply}, analysis: analysis})
       when is_integer(ply) do
    case AnalysisView.current_position(analysis, List.duplicate(0, ply)) do
      {:ok, _node, position} -> to_fen(position)
      _ -> ""
    end
  end

  defp review_fen(_assigns), do: ""

  # On every position change the panel must reflect the CURRENT position: a
  # cached evaluation fills it instantly, anything else resets to the honest
  # analyzing state. A stale evaluation of the previous position never shows.
  defp refresh_engine_position(socket) do
    if socket.assigns.engine_on do
      case cached_engine_eval(socket) do
        {:ok, cached} ->
          preview = engine_preview_from_cache(socket, cached)

          assign(socket,
            engine_preview: preview,
            engine_cached: %{
              fen: preview.fen,
              depth: preview.depth,
              multipv: length(preview.pv)
            },
            engine_peek: nil
          )

        :miss ->
          assign(socket,
            engine_preview: nil,
            engine_pv_cache: %{},
            engine_cached: nil,
            engine_peek: nil
          )
      end
    else
      socket
    end
  end

  # The reference panel combines the opening classification, the corpus move
  # statistics and — in tablebase range — the exact endgame result. It loads
  # asynchronously: corpus aggregation on busy opening positions takes real
  # time and must never block a position change. assign_async replaces
  # superseded runs by key, so fast navigation cannot show stale data.
  defp start_reference(socket) do
    analysis = socket.assigns.analysis
    path = socket.assigns.current_path
    position = socket.assigns.position
    current_node = socket.assigns.current_node

    if is_nil(analysis) or is_nil(position) or is_nil(current_node) do
      socket
    else
      position_id = Node.position_id(current_node)

      assign_async(
        socket,
        :reference,
        fn -> {:ok, %{reference: reference_data(analysis, path, position, position_id)}} end,
        reset: true
      )
    end
  end

  defp reference_data(analysis, path, position, position_id) do
    opening =
      case OpeningBook.classify_line(analysis, path) do
        {:ok, classification} -> classification
        :not_found -> nil
      end

    %{
      opening: opening,
      moves: OpeningBook.moves(position, position_id, limit: 12),
      endgame: endgame_reference(position, position_id)
    }
  end

  # Tablebase range: seven pieces or fewer and no castling rights. Results are
  # cached durably; positions outside the range never reach the service.
  defp endgame_reference(position, position_id) do
    cond do
      length(Chess.Board.pieces(position.board)) > 7 ->
        nil

      position.castling_rights |> MapSet.new() |> MapSet.size() > 0 ->
        %{status: :not_in_tablebase}

      true ->
        case PositionTablebases.get(position_id) do
          {:ok, result} ->
            %{status: :ok, result: result}

          :not_found ->
            case Tablebase.fetch(to_fen(position)) do
              {:ok, result} ->
                :ok = PositionTablebases.put(position_id, result)
                %{status: :ok, result: result}

              {:error, reason} ->
                %{status: reason}
            end
        end
    end
  end

  # The vector feeds the always-visible features column (and any pinned
  # features); it is extracted once per position and stored durably. Tests
  # disable the autoload to avoid paying extraction per rendered position.
  defp maybe_load_features(socket) do
    if not is_nil(socket.assigns.current_node) and
         Application.get_env(:web, :features_autoload, true) do
      load_features(socket)
    else
      socket
    end
  end

  defp load_features(socket) do
    case PositionFeatures.fetch_or_extract(Node.position_id(socket.assigns.current_node)) do
      {:ok, result} ->
        socket
        |> assign(
          features: %{
            version: result.version,
            sections: feature_sections(result.features, socket.assigns.locale),
            values: result.features
          },
          features_status: :ok
        )
        |> assign_highlights()

      {:error, _reason} ->
        assign(socket, features: nil, features_status: :unreachable)
    end
  end

  # Pinning needs the raw vector even with the features tab closed.
  defp toggle_pin(socket, id) do
    socket =
      if socket.assigns.features, do: socket, else: load_features(socket)

    pinned =
      if MapSet.member?(socket.assigns.pinned_features, id),
        do: MapSet.delete(socket.assigns.pinned_features, id),
        else: MapSet.put(socket.assigns.pinned_features, id)

    socket |> assign(:pinned_features, pinned) |> assign_highlights()
  end

  defp assign_highlights(socket) do
    values = (socket.assigns.features && socket.assigns.features.values) || %{}
    hints = feature_board_hints()

    assign(
      socket,
      :feature_highlights,
      compute_highlights(values, socket.assigns.pinned_features, hints, socket.assigns.position)
    )
  end

  # The catalogue's board hints: feature id => piece type(s) to draw from the
  # position when the value itself holds no squares (counts, pairs, ...).
  defp feature_board_hints do
    Map.new(Catalogue.all(), fn feature -> {feature.id, feature.board} end)
  end

  # What feature pinning draws on the board: per-side and neutral squares,
  # file markers, and per-square heat levels (1..3).
  @typep square_highlights :: %{
           required(:white) => MapSet.t(Square.t()),
           required(:black) => MapSet.t(Square.t()),
           required(:neutral) => MapSet.t(Square.t()),
           required(:files) => MapSet.t(non_neg_integer()),
           optional(:white_heat) => %{optional(Square.t()) => pos_integer()},
           optional(:black_heat) => %{optional(Square.t()) => pos_integer()}
         }

  @spec empty_highlights() :: square_highlights()
  defp empty_highlights do
    %{
      white: MapSet.new(),
      black: MapSet.new(),
      neutral: MapSet.new(),
      files: MapSet.new(),
      white_heat: %{},
      black_heat: %{}
    }
  end

  # dialyzer flags the merge below as call_without_opaque: on OTP 29 the
  # inferred representation of MapSet.new() (tuple | map) never matches the
  # opaque :sets.set() in MapSet.union's spec, however the sets are built.
  # The values are genuine MapSets, so the opaque family is suppressed here.
  @dialyzer {:no_opaque, compute_highlights: 4}
  @spec compute_highlights(map(), [String.t()], map(), Position.t() | nil) ::
          square_highlights()
  defp compute_highlights(values, pinned, hints, position) do
    Enum.reduce(pinned, empty_highlights(), fn id, acc ->
      case highlights_for(Map.get(values, id), Map.get(hints, id), position) do
        nil -> acc
        highlights -> merge_highlights(acc, highlights)
      end
    end)
  end

  @spec merge_highlights(square_highlights(), square_highlights()) :: square_highlights()
  defp merge_highlights(a, b) do
    %{
      white: MapSet.union(a.white, b.white),
      black: MapSet.union(a.black, b.black),
      neutral: MapSet.union(a.neutral, b.neutral),
      files: MapSet.union(a.files, b.files),
      white_heat: Map.merge(Map.get(a, :white_heat, %{}), Map.get(b, :white_heat, %{})),
      black_heat: Map.merge(Map.get(a, :black_heat, %{}), Map.get(b, :black_heat, %{}))
    }
  end

  # A board hint draws the catalogue's named piece type(s) from the position
  # for every side the value affirms (counts > 0, flags that are true).
  @spec highlights_for(term(), term(), Position.t() | nil) :: square_highlights() | nil
  defp highlights_for(value, hint, position) when not is_nil(hint) do
    piece_highlights(value, List.wrap(hint), position)
  end

  # What a feature can draw: per-side square lists, plain square lists and
  # file letters ("a"). Other shapes have nothing to pin; empty results too.
  defp highlights_for(%{"white" => white, "black" => black}, _hint, _position)
       when (is_list(white) or is_binary(white)) and (is_list(black) or is_binary(black)) do
    highlights = %{
      white: square_set(white),
      black: square_set(black),
      neutral: MapSet.new(),
      files: MapSet.new()
    }

    if MapSet.size(highlights.white) + MapSet.size(highlights.black) > 0,
      do: highlights,
      else: nil
  end

  # Heat maps are per-side maps of square => count (e.g. mobility.per_piece);
  # they draw in three intensities, normalised to the highest count on the
  # board. Other per-side maps (wing counts, structure) do not draw.
  defp highlights_for(%{"white" => white, "black" => black}, _hint, _position)
       when is_map(white) and is_map(black) do
    if (heat_map?(white) or heat_map?(black)) and heat_max(white, black) > 0 do
      max = heat_max(white, black)

      %{
        white: MapSet.new(),
        black: MapSet.new(),
        neutral: MapSet.new(),
        files: MapSet.new(),
        white_heat: heat_levels(white, max),
        black_heat: heat_levels(black, max)
      }
    end
  end

  defp highlights_for(value, _hint, _position) when is_binary(value) do
    squares = square_set(value)

    if MapSet.size(squares) > 0 do
      %{white: MapSet.new(), black: MapSet.new(), neutral: squares, files: MapSet.new()}
    else
      nil
    end
  end

  defp highlights_for(list, _hint, _position) when is_list(list) and list != [] do
    list = List.flatten(list)

    if file_letters?(list) do
      files = MapSet.new(list, fn letter -> :binary.first(letter) - ?a end)

      if MapSet.size(files) > 0,
        do: %{white: MapSet.new(), black: MapSet.new(), neutral: MapSet.new(), files: files},
        else: nil
    else
      squares = square_set(list)

      if MapSet.size(squares) > 0,
        do: %{white: MapSet.new(), black: MapSet.new(), neutral: squares, files: MapSet.new()},
        else: nil
    end
  end

  defp highlights_for(_value, _hint, _position), do: nil

  # Per-side maps whose keys are all squares and whose values are all numbers
  # are heat maps; wing counts and structure maps are not.
  defp heat_map?(map) when map_size(map) == 0, do: false

  defp heat_map?(map) when is_map(map) do
    Enum.all?(map, fn {square, value} ->
      is_number(value) and is_integer(Square.from_algebraic(square))
    end)
  end

  defp heat_max(white, black) do
    [white, black]
    |> Enum.flat_map(&Map.values/1)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0 end)
  end

  @spec heat_levels(map(), number()) :: %{optional(Square.t()) => pos_integer()}
  defp heat_levels(map, max) do
    if heat_map?(map) do
      for {square, value} <- map, value > 0, into: %{} do
        {Square.from_algebraic(square), max(1, ceil(3 * value / max))}
      end
    else
      %{}
    end
  end

  # Piece highlights resolve their squares from the position; without a
  # position there is nothing to draw.
  @spec piece_highlights(term(), [atom()], Position.t() | nil) :: square_highlights() | nil
  defp piece_highlights(_value, _types, position) when is_nil(position), do: nil

  defp piece_highlights(%{"white" => white, "black" => black}, types, position) do
    highlights = %{
      white: if(truthy?(white), do: piece_squares(position, :white, types), else: MapSet.new()),
      black: if(truthy?(black), do: piece_squares(position, :black, types), else: MapSet.new()),
      neutral: MapSet.new(),
      files: MapSet.new()
    }

    if MapSet.size(highlights.white) + MapSet.size(highlights.black) > 0,
      do: highlights,
      else: nil
  end

  # Scalar flags ("both sides have the pair") highlight both sides.
  defp piece_highlights(true, types, position) do
    piece_highlights(%{"white" => true, "black" => true}, types, position)
  end

  defp piece_highlights(_value, _types, _position), do: nil

  # Numbers are counts (positive = the side has some); booleans are flags.
  defp truthy?(value) when is_number(value), do: value > 0
  defp truthy?(value), do: value == true

  @spec piece_squares(Position.t(), :white | :black, [atom()]) :: MapSet.t(Square.t())
  defp piece_squares(position, color, types) do
    position
    |> Position.pieces()
    |> Enum.filter(fn {_square, {piece_color, type}} ->
      piece_color == color and type in types
    end)
    |> MapSet.new(fn {square, _piece} -> square end)
  end

  @spec square_set(binary() | [term()]) :: MapSet.t(Square.t())
  defp square_set(value) when is_binary(value), do: square_set([value])

  defp square_set(list) when is_list(list) do
    list
    |> List.flatten()
    |> Enum.reduce(MapSet.new(), fn value, acc ->
      case Square.from_algebraic(value) do
        square when is_integer(square) -> MapSet.put(acc, square)
        _ -> acc
      end
    end)
  end

  defp file_letters?(list) do
    Enum.all?(list, fn value ->
      is_binary(value) and byte_size(value) == 1 and value in ~w(a b c d e f g h)
    end)
  end

  # Catalogue features in spec-section order, with humanized labels, the
  # stored values and the board hint (nil for square-level features).
  defp feature_sections(values, locale) do
    Catalogue.all()
    |> Enum.group_by(& &1.section)
    |> Enum.sort_by(fn {section, _features} -> section end)
    |> Enum.map(fn {section, features} ->
      {section,
       Enum.map(features, fn feature ->
         {feature.id, feature_label(feature.id, locale), Map.get(values, feature.id),
          feature.board}
       end)}
    end)
  end

  # Rows that can draw on the board get a small cue; the engine decides.
  defp feature_drawable?(value, hint, position) do
    not is_nil(highlights_for(value, hint, position))
  end

  # The label is the id humanized; ids that carry Dutch words or typos have
  # curated label overrides in the catalog.
  defp feature_label(id, locale) do
    key = "featureLabels." <> id

    case Web.I18n.t(key, locale) do
      ^key -> id |> String.split(".", parts: 2) |> List.last() |> humanize()
      text -> text
    end
  end

  defp humanize(slug) when is_binary(slug) do
    words = slug |> String.replace(".", " ") |> String.replace("_", " ")

    case words do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      _ -> words
    end
  end

  defp humanize(_slug), do: ""

  # Per-side maps are the catalogue's most common shape; render them per
  # side instead of counting keys. Booleans become the true sides.
  defp feature_value(%{"white" => white, "black" => black}, locale)
       when is_boolean(white) and is_boolean(black) do
    case {white, black} do
      {false, false} -> "—"
      {true, true} -> Web.I18n.t("room.featureBoth", locale)
      {true, false} -> Web.I18n.t("room.endgameWhite", locale)
      {false, true} -> Web.I18n.t("room.endgameBlack", locale)
    end
  end

  defp feature_value(%{"white" => white, "black" => black}, locale) do
    "#{Web.I18n.t("room.featureWhiteInitial", locale)} #{feature_side_value(white, locale)} · " <>
      "#{Web.I18n.t("room.featureBlackInitial", locale)} #{feature_side_value(black, locale)}"
  end

  defp feature_value(value, locale) do
    cond do
      is_binary(value) -> value
      is_float(value) -> value |> Float.round(2) |> to_string()
      is_integer(value) -> Integer.to_string(value)
      is_boolean(value) -> Web.I18n.t(if(value, do: "common.yes", else: "common.no"), locale)
      is_list(value) -> feature_list_value(value)
      is_map(value) -> Integer.to_string(map_size(value))
      is_nil(value) -> "—"
      true -> to_string(value)
    end
  end

  # Short lists of short strings read better than a count (open files "a, d").
  defp feature_list_value(list) do
    if length(list) in 1..4 and Enum.all?(list, &(is_binary(&1) and String.length(&1) <= 3)) do
      Enum.join(list, ", ")
    else
      Integer.to_string(length(list))
    end
  end

  defp feature_side_value(value, locale) when is_boolean(value),
    do: Web.I18n.t(if(value, do: "common.yes", else: "common.no"), locale)

  defp feature_side_value(value, _locale) when is_binary(value), do: value
  defp feature_side_value(value, _locale) when is_integer(value), do: Integer.to_string(value)

  defp feature_side_value(value, _locale) when is_float(value),
    do: Float.round(value, 2) |> to_string()

  defp feature_side_value(value, _locale) when is_list(value), do: feature_list_value(value)

  # A side can hold a map (piece occupancy: type to squares); show the total
  # of the listed squares so "16 pieces" reads naturally.
  defp feature_side_value(value, _locale) when is_map(value) do
    values = Map.values(value)

    if values != [] and Enum.all?(values, &is_list/1) do
      values |> Enum.map(&length/1) |> Enum.sum() |> Integer.to_string()
    else
      Integer.to_string(map_size(value))
    end
  end

  defp feature_side_value(nil, _locale), do: "—"
  defp feature_side_value(value, _locale), do: to_string(value)

  # Rows with nothing in this position (no squares, false, empty lists) dim;
  # they still open their description but draw nothing on the board.
  defp feature_empty?(nil), do: true
  defp feature_empty?(false), do: true
  defp feature_empty?(""), do: true
  defp feature_empty?([]), do: true

  defp feature_empty?(%{"white" => white, "black" => black}),
    do: feature_empty?(white) and feature_empty?(black)

  defp feature_empty?(map) when is_map(map), do: map_size(map) == 0
  defp feature_empty?(_value), do: false

  # The comment marker on the moves-panel header button.
  defp comment_present?(nil), do: false
  defp comment_present?(%Node{comment: comment}), do: is_binary(comment) and comment != ""

  # Template view of the async reference assign.
  defp reference_view(%Phoenix.LiveView.AsyncResult{loading: loading}) when loading, do: :loading

  defp reference_view(%Phoenix.LiveView.AsyncResult{failed: failed}) when not is_nil(failed),
    do: :failed

  defp reference_view(%Phoenix.LiveView.AsyncResult{result: result}) when not is_nil(result),
    do: {:ok, result}

  defp reference_view(_), do: :none

  # The detail strip answers "what does this mean": the curated description
  # from the catalog, the raw id, and the raw value the row summarizes.
  defp feature_description(id, locale) do
    key = "features." <> id

    case Web.I18n.t(key, locale) do
      ^key -> Web.I18n.t("room.featuresNoDescription", locale)
      text -> text
    end
  end

  defp feature_detail_raw(id, values) do
    values
    |> Map.get(id)
    |> inspect(pretty: true, limit: :infinity)
    |> String.slice(0, 2_000)
  end

  # A cached evaluation covers the request only when it is at least as deep
  # AND computed with at least as many lines — a cache row always carries
  # every line that was computed, so coverage is honest on both axes.
  defp cached_engine_eval(socket) do
    with %Node{} = node <- socket.assigns.current_node,
         {:ok, cached} <- PositionEvals.get(Node.position_id(node), @engine_id),
         true <- cached.depth >= socket.assigns.engine_settings.depth,
         true <- cached.multipv >= socket.assigns.engine_settings.multipv do
      {:ok, cached}
    else
      _ -> :miss
    end
  end

  # Cached evaluations are stored white-relative, matching the panel. Every
  # computed line comes back, so the panel can serve any MultiPV request the
  # cache covers; the template shows the first requested ones.
  defp engine_preview_from_cache(socket, cached) do
    position = socket.assigns.position
    context = AnalysisView.move_context(socket.assigns.analysis, socket.assigns.current_path)

    pv =
      cached.lines
      |> Enum.map(fn line ->
        moves =
          (line["pv"] || "")
          |> String.split(" ", trim: true)
          |> Enum.zip(UCI.pv_to_san(position, line["pv"] || ""))
          |> Enum.map(fn {uci, san} -> %{uci: uci, san: san} end)

        case moves do
          [] ->
            nil

          _ ->
            %{
              multipv: engine_int(line["multipv"]),
              score: eval_label(%{eval_cp: line["score_cp"], mate_in: line["score_mate"]}),
              moves: add_move_labels(moves, context)
            }
        end
      end)
      |> Enum.reject(&is_nil/1)

    %{
      fen: current_fen(socket),
      eval_cp: cached.eval_cp,
      mate_in: cached.mate,
      depth: cached.depth,
      nodes: cached.nodes,
      nps: nil,
      pv: pv
    }
  end

  # Fills the evaluation graph from the cache for every mainline position.
  defp merge_cached_graph_evals(socket) do
    case mainline_position_ids(socket) do
      [] ->
        socket

      ids ->
        cached = PositionEvals.get_many(ids, @engine_id)

        evals =
          Map.new(cached, fn {id, eval} ->
            {id,
             %{
               cp: eval.eval_cp,
               mate: eval.mate,
               label: eval_label(%{eval_cp: eval.eval_cp, mate_in: eval.mate})
             }}
          end)

        assign(socket, :engine_evals, Map.merge(evals, socket.assigns.engine_evals))
    end
  end

  defp mainline_position_ids(socket) do
    case socket.assigns.analysis do
      %AnalysisModel{} = analysis ->
        for ply <- 0..socket.assigns.mainline_length,
            node = AnalysisModel.node_at(analysis, List.duplicate(0, ply)),
            not is_nil(node) do
          Node.position_id(node)
        end

      _ ->
        []
    end
  end

  # Persists a completed search with every computed line; deepest-wins upsert
  # keeps the best result.
  defp persist_engine_eval(socket, preview, lines) do
    case socket.assigns.current_node do
      %Node{} = node ->
        first_pv = lines |> List.first() |> then(&(&1 && &1["pv"]))

        PositionEvals.put(Node.position_id(node), @engine_id, %{
          depth: preview.depth,
          eval_cp: preview.eval_cp,
          mate: preview.mate_in,
          best_move: first_pv && first_pv |> String.split(" ") |> List.first(),
          pv: first_pv,
          nodes: preview.nodes,
          multipv: length(lines),
          lines:
            Enum.map(lines, fn line ->
              %{"multipv" => engine_int(line["multipv"]), "pv" => line["pv"]}
              |> maybe_put_score("score_cp", line["score_cp"])
              |> maybe_put_score("score_mate", line["score_mate"])
            end)
        })

      _ ->
        :ok
    end
  end

  defp maybe_put_score(map, _key, nil), do: map
  defp maybe_put_score(map, key, value), do: Map.put(map, key, engine_int(value))

  # Marks only color the graph once the review classified them.
  defp review_marks(%{status: :done, marks: marks}), do: marks
  defp review_marks(_review), do: %{}

  # Merges a completed review's marks into the move list. Marks are keyed by
  # the ply the move was played from; the move's entry sits one ply deeper.
  defp with_review_marks(move_list, review) do
    case review_marks(review) do
      marks when marks == %{} ->
        move_list

      marks ->
        %{
          move_list
          | entries: Enum.map(move_list.entries, &mark_entry(&1, marks)),
            rows: Enum.map(move_list.rows, &mark_row(&1, marks))
        }
    end
  end

  defp mark_row(%{type: :mainline, moves: moves} = row, marks) do
    %{row | moves: Enum.map(moves, fn move -> %{move | entry: mark_entry(move.entry, marks)} end)}
  end

  defp mark_row(row, _marks), do: row

  defp mark_entry(entry, marks) do
    if entry.path != [] and Enum.all?(entry.path, &(&1 == 0)) do
      case marks[length(entry.path) - 1] do
        nil -> entry
        mark -> Map.put(entry, :review, mark)
      end
    else
      entry
    end
  end

  # Critical moments for the review summary: the biggest swings, worst first.
  defp review_critical_moments(move_entries, review) do
    review.marks
    |> Enum.sort_by(fn {_ply, mark} -> -mark.loss end)
    |> Enum.take(5)
    |> Enum.map(fn {ply, mark} ->
      path = List.duplicate(0, ply + 1)
      entry = Enum.find(move_entries, &(&1.path == path))

      %{
        ply: ply,
        mark: mark.mark,
        label: if(entry, do: "#{entry.prefix} #{entry.label}", else: ""),
        path: Enum.join(path, ",")
      }
    end)
  end

  defp engine_int(value) when is_integer(value), do: value

  defp engine_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> 0
    end
  end

  defp engine_int(_value), do: 0

  defp current_fen(%{assigns: %{position: %Chess.Position{} = position}}),
    do: to_fen(position)

  defp current_fen(_socket), do: nil

  @search_page_size 25

  # One bounded GameSearch page per request; entries arrive occurrence-level
  # (one row per position a game passes through) and the list shows one row
  # per game record, keeping the first occurrence it reached.
  defp run_corpus_search(socket, filters) do
    case corpus_search(filters, nil) do
      {:ok, results, cursor} ->
        {:noreply,
         assign(socket,
           search_filters: filters,
           search_results: results,
           search_cursor: cursor,
           search_error: nil,
           search_counts: search_interpretation_counts(filters)
         )}

      {:error, :invalid_fen} ->
        {:noreply,
         assign(socket,
           search_filters: filters,
           search_results: [],
           search_cursor: nil,
           search_error: "room.searchInvalidFen",
           search_counts: nil
         )}

      {:error, :invalid_move_line} ->
        {:noreply,
         assign(socket,
           search_filters: filters,
           search_results: [],
           search_cursor: nil,
           search_error: "room.searchInvalidMoveLine",
           search_counts: nil
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           search_filters: filters,
           search_results: [],
           search_cursor: nil,
           search_error: "room.searchFailed",
           search_counts: nil
         )}
    end
  end

  # How many games each FEN interpretation reaches (the interpretation tabs).
  # Only computed with a parseable position present.
  defp search_interpretation_counts(filters) do
    case FEN.parse(String.trim(to_string(filters["fen"]))) do
      {:ok, %{position: position}} ->
        record_query = search_record_query(filters)

        exact =
          GameSearch.count_matches(
            Analysis.PositionQuery.equivalent(position),
            record_query
          )

        similar =
          GameSearch.similar_count(
            position,
            record_query,
            substitution_option(filters["material_substitution"])
          )

        structure =
          GameSearch.count_matches(
            Analysis.PositionQuery.pawn_structure(position),
            record_query
          )

        case {exact, similar, structure} do
          {{:ok, exact}, {:ok, similar}, {:ok, structure}} ->
            %{exact: exact, similar: similar, structure: structure}

          _other ->
            nil
        end

      _invalid_fen ->
        nil
    end
  end

  defp corpus_search(filters, cursor) do
    if blank_to_nil(filters["move_line"]) do
      corpus_search_move_line(filters, cursor)
    else
      # Similar mode only applies with a position; metadata-only searches
      # page newest-first regardless of the selected mode.
      if filters["position_mode"] == "similar" and not is_nil(blank_to_nil(filters["fen"])) do
        corpus_search_similar(filters, cursor)
      else
        atoms = search_atoms(filters["features"])

        with {:ok, position_query} <-
               search_position_query(filters["fen"], filters["position_mode"], atoms) do
          record_query = search_record_query(filters)

          # With a position filter (FEN or feature atoms) the scan stays
          # position-driven (insertion order); game-only searches page newest-first.
          sort =
            if blank_to_nil(filters["fen"]) || atoms != [],
              do: :insertion,
              else: :date_desc

          options =
            if cursor,
              do: [limit: @search_page_size, cursor: cursor, sort: sort],
              else: [limit: @search_page_size, sort: sort]

          case GameSearch.page(position_query, record_query, options) do
            {:ok, page} ->
              build_corpus_results(page.entries, page.next)

            {:error, _reason} ->
              {:error, :search_failed}
          end
        end
      end
    end
  end

  # Move line search ("1. e4 c5 2. Nf3 d6"): every position of the line at
  # its own ply, starting from the FEN position when given, else the start.
  defp corpus_search_move_line(filters, cursor) do
    case parse_move_line(filters["fen"], filters["move_line"]) do
      {:ok, positions} ->
        record_query = search_record_query(filters)

        options =
          if cursor,
            do: [limit: @search_page_size, cursor: cursor],
            else: [limit: @search_page_size]

        case GameSearch.move_line(positions, record_query, options) do
          {:ok, page} ->
            build_corpus_results(page.entries, page.next)

          {:error, _reason} ->
            {:error, :search_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @move_line_max_plies 30

  defp parse_move_line(fen, line) do
    with {:ok, start_position} <- start_position_for_line(fen),
         {:ok, sans} <- move_line_tokens(line) do
      replay_move_line(start_position, sans, [start_position])
    end
  end

  defp start_position_for_line(fen) do
    case blank_to_nil(fen) do
      nil ->
        {:ok, Position.starting_position()}

      _ ->
        case FEN.parse(String.trim(fen)) do
          {:ok, %{position: position}} -> {:ok, position}
          _invalid -> {:error, :invalid_fen}
        end
    end
  end

  defp move_line_tokens(line) do
    tokens =
      line
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(&1 =~ ~r/^\d+\.*$/))
      |> Enum.reject(&(&1 in ["1-0", "0-1", "1/2-1/2", "*"]))

    if tokens == [] or length(tokens) > @move_line_max_plies do
      {:error, :invalid_move_line}
    else
      {:ok, tokens}
    end
  end

  defp replay_move_line(_position, [], positions), do: {:ok, Enum.reverse(positions)}

  defp replay_move_line(position, [san | rest], positions) do
    case Chess.Notation.SAN.parse(position, san) do
      {:ok, move} ->
        case Position.apply_move(position, move) do
          {:ok, next_position} ->
            replay_move_line(next_position, rest, [next_position | positions])

          {:error, _reason} ->
            {:error, :invalid_move_line}
        end

      {:error, _reason} ->
        {:error, :invalid_move_line}
    end
  end

  # Search-by-example: the FEN position's atoms drive the ranking.
  defp corpus_search_similar(filters, cursor) do
    case FEN.parse(String.trim(to_string(filters["fen"]))) do
      {:ok, %{position: position}} ->
        record_query = search_record_query(filters)

        options =
          [limit: @search_page_size]
          |> then(fn options ->
            if cursor, do: Keyword.put(options, :cursor, cursor), else: options
          end)
          |> then(fn options ->
            case parse_substitution(filters["material_substitution"]) do
              nil -> options
              substitution -> Keyword.put(options, :substitution, substitution)
            end
          end)

        case GameSearch.similar(position, record_query, options) do
          {:ok, page} ->
            build_corpus_results(page.entries, page.next, page.query_total)

          {:error, _reason} ->
            {:error, :search_failed}
        end

      _ ->
        {:error, :invalid_fen}
    end
  end

  defp parse_substitution("two_rooks_queen"), do: :two_rooks_queen
  defp parse_substitution("bishop_knight"), do: :bishop_knight
  defp parse_substitution(_other), do: nil

  defp substitution_option(value) do
    case parse_substitution(value) do
      nil -> []
      substitution -> [substitution: substitution]
    end
  end

  defp build_corpus_results(entries, next_cursor, query_total \\ nil) do
    {results, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, seen} ->
        {record, occurrence, shared} = corpus_entry(entry)

        if MapSet.member?(seen, record.id) do
          {acc, seen}
        else
          {[corpus_result(record, occurrence, shared, query_total) | acc],
           MapSet.put(seen, record.id)}
        end
      end)

    {:ok, Enum.reverse(results) |> with_corpus_positions(), next_cursor}
  end

  defp corpus_entry({record, occurrence}), do: {record, occurrence, nil}
  defp corpus_entry({record, occurrence, shared}), do: {record, occurrence, shared}

  defp search_position_query(fen, _mode, atoms) when fen in ["", nil] and atoms == [],
    do: {:ok, true}

  defp search_position_query(fen, _mode, atoms) when fen in ["", nil] do
    {:ok, Analysis.PositionQuery.digests(atoms)}
  end

  defp search_position_query(fen, mode, atoms) do
    case FEN.parse(String.trim(to_string(fen))) do
      {:ok, %{position: position}} ->
        fen_query =
          case mode do
            "exact_color_swapped" ->
              Analysis.PositionQuery.any([
                Analysis.PositionQuery.equivalent(position),
                Analysis.PositionQuery.equivalent(Position.color_swapped(position))
              ])

            "exact_mirrored" ->
              Analysis.PositionQuery.any([
                Analysis.PositionQuery.equivalent(position),
                Analysis.PositionQuery.equivalent(Position.file_reflected(position))
              ])

            "structure" ->
              Analysis.PositionQuery.pawn_structure(position)

            "structure_symmetries" ->
              Analysis.PositionQuery.pawn_structure_symmetries(position)

            "structure_edit1" ->
              Analysis.PositionQuery.pawn_structure_edit_neighborhood(position, 1)

            "structure_push" ->
              Analysis.PositionQuery.pawn_structure_single_push_neighborhood(position)

            "structure_missing" ->
              Analysis.PositionQuery.pawn_structure_missing_pawn_neighborhood(position)

            "structure_color_reversed" ->
              Analysis.PositionQuery.color_reversed_pawn_structure(position)

            "structure_reflected" ->
              Analysis.PositionQuery.file_reflected_pawn_structure(position)

            _ ->
              Analysis.PositionQuery.equivalent(position)
          end

        {:ok,
         case atoms do
           [] -> fen_query
           atoms -> Analysis.PositionQuery.all([fen_query, Analysis.PositionQuery.digests(atoms)])
         end}

      _ ->
        {:error, :invalid_fen}
    end
  end

  # The form's features[] checkboxes arrive as a list (several), one string
  # (exactly one) or nil (none).
  defp search_atoms(nil), do: []
  defp search_atoms(atoms) when is_list(atoms), do: Enum.uniq(atoms)
  defp search_atoms(atom) when is_binary(atom), do: [atom]

  # The picker's atoms per catalogue section: the full searchable
  # vocabulary of the feature catalogue (see
  # Analysis.FeatureDigest.picker_atoms/1), not a curated subset. Labels
  # resolve through the same feature_label used by the features panel.

  defp search_feature_groups(locale) do
    for {section, atoms} <- PositionFeatures.search_picker_groups() do
      {section,
       Enum.map(atoms, fn atom ->
         {atom, search_atom_label(atom, locale)}
       end)}
    end
  end

  defp search_atom_label(atom, locale) do
    case String.split(atom, ":") do
      [id] ->
        feature_label(id, locale)

      [id, side] ->
        side_label =
          Web.I18n.t(
            if(side == "w", do: "room.searchColourWhite", else: "room.searchColourBlack"),
            locale
          )

        "#{feature_label(id, locale)} (#{String.downcase(side_label)})"
    end
  end

  defp search_record_query(filters) do
    player = filters["player"] |> to_string() |> String.trim()

    player_queries =
      case {player, filters["color"]} do
        {"", _} ->
          []

        {name, "white"} ->
          [GameRecordQuery.metadata_value_contains("white", name)]

        {name, "black"} ->
          [GameRecordQuery.metadata_value_contains("black", name)]

        {name, _color} ->
          [
            GameRecordQuery.any([
              GameRecordQuery.metadata_value_contains("white", name),
              GameRecordQuery.metadata_value_contains("black", name)
            ])
          ]
      end

    result_queries =
      if filters["result"] in ["1-0", "0-1", "1/2-1/2", "*"],
        do: [GameRecordQuery.metadata_contains(%{"result" => filters["result"]})],
        else: []

    # Free-text metadata: substring matches, case-insensitive.
    text_queries =
      for key <- ["eco", "opening", "event"],
          value = blank_to_nil(filters[key]),
          value != nil do
        GameRecordQuery.metadata_value_contains(key, value)
      end

    # Rating bounds apply to both players; the corpus stores Elos as strings.
    rating_queries =
      case {parse_rating(filters["rating_min"]), parse_rating(filters["rating_max"])} do
        {nil, nil} ->
          []

        {minimum, maximum} ->
          for key <- ["white_elo", "black_elo"] do
            GameRecordQuery.metadata_int_between(key, minimum, maximum)
          end
      end

    date_queries =
      case {blank_to_nil(filters["date_from"]), blank_to_nil(filters["date_to"])} do
        {nil, nil} -> []
        {from, to} -> [GameRecordQuery.metadata_value_between("date", from, to)]
      end

    case player_queries ++ result_queries ++ text_queries ++ rating_queries ++ date_queries do
      [] -> GameRecordQuery.match_all()
      [single] -> single
      queries -> GameRecordQuery.all(queries)
    end
  end

  defp corpus_result(record, occurrence, shared, query_total) do
    metadata = record.metadata

    opening_label =
      case Enum.filter([metadata["eco"], metadata["opening"]], & &1) do
        [] -> nil
        parts -> Enum.join(parts, " ")
      end

    match_pct =
      case {shared, query_total} do
        {shared, query_total}
        when is_integer(shared) and is_integer(query_total) and query_total > 0 ->
          round(shared / query_total * 100)

        _ ->
          nil
      end

    %{
      id: record.id,
      white: metadata["white"] || "?",
      black: metadata["black"] || "?",
      opening: opening_label,
      event: metadata["event"],
      date: metadata["date"],
      result: metadata["result"] || "*",
      ply: if(occurrence, do: occurrence.ply, else: 0),
      position_id: if(occurrence, do: occurrence.position_id, else: nil),
      position: nil,
      match_pct: match_pct
    }
  end

  # One extra query per page: the matched positions become the row previews.
  defp with_corpus_positions(results) do
    positions =
      results
      |> Enum.map(& &1.position_id)
      |> Enum.reject(&is_nil/1)
      |> PositionStore.get_many()

    Enum.map(results, &Map.put(&1, :position, Map.get(positions, &1.position_id)))
  end

  defp parse_ply(value) when is_binary(value) do
    case Integer.parse(value) do
      {ply, ""} when ply in 0..999 -> ply
      _ -> 0
    end
  end

  defp parse_ply(_value), do: 0

  defp parse_rating(value) do
    case Integer.parse(to_string(value) |> String.trim()) do
      {rating, ""} when rating in 0..4000 -> rating
      _ -> nil
    end
  end

  defp blank_to_nil(value) do
    case to_string(value) |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # The peek board renders the position in visual order following the main
  # board's orientation: White at the bottom by default.
  defp peek_squares(position, orientation) do
    {ranks, files} =
      if orientation == "black",
        do: {Enum.to_list(0..7), Enum.to_list(7..0//-1)},
        else: {Enum.to_list(7..0//-1), Enum.to_list(0..7)}

    for rank <- ranks, file <- files do
      square = rank * 8 + file

      %{
        square: square,
        piece: Position.piece_at(position, square),
        light: rem(file + rank, 2) == 1
      }
    end
  end

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
