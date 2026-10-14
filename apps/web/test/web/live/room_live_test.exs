defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Analyses
  alias Analysis.GameRecords
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Rooms
  alias Chess.Move
  alias Chess.Position
  alias Web.AnalysisView
  alias Web.DemoData

  setup do
    Application.ensure_all_started(:analysis)
    code = "LV" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)
    {:ok, code: code}
  end

  test "renders an empty room and starts an analysis", %{conn: conn, code: code} do
    {:ok, view, html} = live(conn, "/rooms/#{code}")

    assert html =~ "No analyses in this room yet"
    html = render_click(view, "create-analysis", %{})
    assert html =~ "id=\"chess-board\""
    assert html =~ "Chessboard"
    assert html =~ "/images/pieces/merida/white_pawn.svg"

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, _analysis, _revision} = Analyses.get(analysis_id)
  end

  test "saved analysis links restore moves after their room worker stops", %{
    conn: conn,
    code: code
  } do
    {:ok, first_view, _html} = live(conn, "/rooms/#{code}")
    render_click(first_view, "create-analysis", %{})

    first_view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    analysis_id = room_analysis_id!(code)
    saved_url = "/rooms/#{code}?a=#{analysis_id}"

    [{worker, _value}] = Horde.Registry.lookup(Analysis.RoomRegistry, code)
    ref = Process.monitor(worker)
    assert :ok = Horde.DynamicSupervisor.terminate_child(Analysis.RoomSupervisor, worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1_000
    assert :ok = wait_until_room_unregistered(code)

    {:ok, restored_view, html} = live(build_conn(), saved_url)

    # Analysis deep links select the analysis, but start at its root position.
    assert html =~ ~s(data-move-path="0")
    assert html =~ ~s(aria-label="occupied by white pawn e2")

    # Selecting the saved move must display its durable resulting position.
    html = render_click(restored_view, "last-move", %{})
    assert html =~ ~s(aria-label="occupied by white pawn e4")
    assert html =~ "1/1"

    assert {:ok, restored_room} = Rooms.get(code)
    assert analysis_id in Analysis.Room.analysis_ids(restored_room)
  end

  test "sharing a selected move creates a deep link that restores its position", %{
    conn: conn,
    code: code
  } do
    {:ok, first, _html} = live(conn, "/rooms/#{code}")
    render_click(first, "create-analysis", %{})

    first
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    assert render(first) =~ ~s(aria-label="occupied by white pawn e4")
    analysis_id = room_analysis_id!(code)
    url = "/rooms/#{code}?a=#{analysis_id}&p=0"

    render_click(first, "copy-room-link", %{})

    copied_notice = Web.I18n.t("common.copied", "en")

    assert_push_event(first, "copy-text", %{
      text: ^url,
      notice: ^copied_notice
    })

    {:ok, restored, html} = live(build_conn(), url)
    assert html =~ ~s(aria-label="occupied by white pawn e4")
    assert html =~ "1/1"
    assert render(restored) =~ ~s(data-move-path="0")
  end

  test "playing and navigating moves keeps the room URL synchronized", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    analysis_id = room_analysis_id!(code)
    root_url = "/rooms/#{code}?a=#{analysis_id}"
    first_move_url = root_url <> "&p=0"

    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    assert_patch(view, first_move_url)
    assert render(view) =~ ~s(aria-label="occupied by white pawn e4")

    render_click(view, "first-move", %{})
    assert_patch(view, root_url)
    assert render(view) =~ ~s(aria-label="occupied by white pawn e2")

    render_click(view, "next-move", %{})
    assert_patch(view, first_move_url)
    assert render(view) =~ ~s(aria-label="occupied by white pawn e4")

    render_click(view, "previous-move", %{})
    assert_patch(view, root_url)
    assert render(view) =~ ~s(aria-label="occupied by white pawn e2")

    # A fresh LiveView can always restore the current bookmarkable move link.
    {:ok, _restored, html} = live(build_conn(), first_move_url)
    assert html =~ ~s(aria-label="occupied by white pawn e4")
  end

  test "a move link with an invalid path falls back to the root position", %{
    conn: conn,
    code: code
  } do
    {:ok, first, _html} = live(conn, "/rooms/#{code}")
    render_click(first, "create-analysis", %{})

    first
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    analysis_id = room_analysis_id!(code)
    {:ok, _restored, html} = live(build_conn(), "/rooms/#{code}?a=#{analysis_id}&p=999")

    assert html =~ ~s(aria-label="occupied by white pawn e2")
    assert html =~ "0/1"
    assert html =~ ~s(data-move-path="0")
  end

  test "unknown room links never create durable rooms", %{conn: conn} do
    code = "UN" <> Base.encode16(:crypto.strong_rand_bytes(2))
    on_exit(fn -> Rooms.stop_room(code) end)
    assert :not_found = Rooms.get(code)
    assert :not_found = Analysis.RoomStore.get(code)

    {:ok, view, html} = live(conn, "/rooms/#{code}")
    assert html =~ "OpenChessLab"
    refute html =~ ~s(id="room-shell")

    assert :not_found = Rooms.get(code)
    assert :not_found = Analysis.RoomStore.get(code)
    assert render(view) =~ "OpenChessLab"
  end

  test "a completed board drag is validated and persisted as a move", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    _html = render_click(view, "create-analysis", %{})

    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    [child] = Node.children(AnalysisModel.root(analysis))
    assert {:ok, position} = PositionStore.get(Node.position_id(child))
    assert Position.piece_at(position, 28) == {:white, :pawn}
  end

  test "position editing removes a palette piece when the same piece occupies the clicked square",
       %{
         conn: conn,
         code: code
       } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "toggle-position-editor", %{})
    render_click(view, "arm-piece", %{"piece" => "white_king"})

    html = render_click(view, "board-square", %{"square" => 4})

    assert html =~ "empty e1"
    refute html =~ "occupied by white king e1"

    assert html =~ "data-pending-edit"

    html = render_click(view, "apply-pending-edit", %{})
    assert html =~ "Edits not stored yet"
    assert html =~ "Each side needs exactly one king."
    assert html =~ "data-pending-edit"
  end

  test "clicking the armed piece removes its matching board piece and keeps edit notice beside board",
       %{
         conn: conn,
         code: code
       } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "toggle-position-editor", %{})
    render_click(view, "arm-piece", %{"piece" => "white_king"})

    html = render_click(view, "board-square", %{"square" => 4})

    assert html =~ "empty e1"
    refute html =~ "occupied by white king e1"

    assert html =~ "data-pending-edit"

    html = render_click(view, "apply-pending-edit", %{})
    assert html =~ "Edits not stored yet"
    assert html =~ "data-pending-edit"
  end

  test "closing the position editor keeps the draft and its apply bar", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "toggle-position-editor", %{})
    render_click(view, "palette-drop", %{"piece" => "white_knight", "square" => "18"})

    html = render_click(view, "toggle-position-editor", %{})

    refute html =~ ~r/<aside[^>]*aria-label="Edit this position"/
    assert html =~ "data-pending-edit"
  end

  test "an open position editor turns board drags into drafts", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "toggle-position-editor", %{})

    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    assert render(view) =~ "data-pending-edit"

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    assert Node.children(AnalysisModel.root(analysis)) == []
  end

  test "click-selecting a piece and target square plays a legal move", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    _html = render_click(view, "create-analysis", %{})

    view
    |> element("#chess-board-square-e2")
    |> render_click()

    html =
      view
      |> element("#chess-board-square-e4")
      |> render_click()

    assert html =~ "1."

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    [child] = Node.children(AnalysisModel.root(analysis))
    assert {:ok, position} = PositionStore.get(Node.position_id(child))
    assert Position.piece_at(position, 28) == {:white, :pawn}
  end

  test "game search uses clearly labelled local fixtures", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")

    html =
      view
      |> render_click("open-search", %{})
      |> then(fn _ ->
        render_submit(view, "search-games", %{
          "player" => "Alice",
          "color" => "either",
          "result" => "either",
          "opening" => ""
        })
      end)

    assert html =~ "DEMO search uses a few local fixtures"
    assert html =~ "Alice Example"
  end

  test "presence and chat are shared by LiveViews in the same room", %{conn: conn, code: code} do
    {:ok, first, _html} = live(conn, "/rooms/#{code}")
    {:ok, second, _html} = live(build_conn(), "/rooms/#{code}")

    assert render(first) =~ "2 people here"
    assert render(second) =~ "2 people here"

    names =
      "room:#{code}"
      |> Web.Presence.list()
      |> Map.values()
      |> Enum.flat_map(& &1.metas)
      |> Enum.map(& &1.display_name)

    assert length(names) == 2
    assert Enum.all?(names, &Regex.match?(~r/\A[A-Z][a-z]+ [A-Z][a-z]+ [1-9][0-9]\z/, &1))

    render_submit(first, "send-chat", %{"message" => "hello from LiveView"})

    assert render(second) =~ "hello from LiveView"
    assert {:ok, messages} = Rooms.chat(code)
    assert Enum.any?(messages, &(&1.text == "hello from LiveView" and &1.author in names))
  end

  test "analysis mutations arrive in other LiveViews sharing the room", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("shared-analysis")
    :ok = Rooms.add_analysis(code, analysis.id)

    {:ok, first, _html} = live(conn, "/rooms/#{code}?a=shared-analysis")
    {:ok, second, _html} = live(build_conn(), "/rooms/#{code}?a=shared-analysis")

    first
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    html = render(second)
    assert html =~ "occupied by white pawn e4"
    assert html =~ "1/1"
  end

  test "a PGN file upload is durably imported into a room analysis",
       %{
         conn: conn,
         code: code
       } do
    {:ok, view, _html} =
      live(
        conn,
        "/rooms/#{code}"
      )

    render_click(
      view,
      "open-import",
      %{}
    )

    upload =
      file_input(
        view,
        "#pgn-import-form",
        :pgn,
        [
          %{
            name: "sample.pgn",
            content: DemoData.game("demo-ruy-lopez").pgn,
            type: "application/x-chess-pgn"
          }
        ]
      )

    render_upload(
      upload,
      "sample.pgn"
    )

    render_submit(
      view,
      "import-pgn",
      %{
        "pgn_text" => ""
      }
    )

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    assert length(
             AnalysisView.move_entries(
               analysis,
               "en"
             )
           ) ==
             10

    assert is_binary(analysis.source_game_record_id)

    assert {
             :ok,
             _record,
             content,
             occurrences
           } =
             GameRecords.load(analysis.source_game_record_id)

    assert length(content.moves) ==
             10

    assert length(occurrences) ==
             11
  end

  test "a pasted PGN imports into a room analysis", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    html = render_click(view, "open-import", %{})

    # The paste textarea must not share its name with the upload's file input:
    # LiveView drops File entries by name, which would wipe the pasted text too.
    assert html =~ ~s(name="pgn_text")

    render_submit(view, "import-pgn", %{
      "pgn_text" => DemoData.game("demo-ruy-lopez").pgn
    })

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    assert length(AnalysisView.move_entries(analysis, "en")) == 10
  end

  test "the mobile shell renders the tab strip and panels", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    html = render(view)

    assert html =~ ~s(phx-hook="RoomTabs")
    assert html =~ ~s(data-tab="moves")
    assert html =~ ~s(data-tab="games")
    assert html =~ ~s(data-tab="chat")
    assert html =~ ~s(data-mobile-panel="games")
    assert html =~ ~s(data-mobile-panel="chat")
    assert html =~ ~s(data-mobile-panel="moves")
    refute html =~ "toggle-chat"
  end

  test "the import dialog keeps one height when switching source tabs", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    html = render_click(view, "open-import", %{})

    assert html =~ "h-[min(35rem,calc(100dvh-2rem))]"

    html = render_click(view, "set-import-source", %{"source" => "library"})
    assert html =~ "h-[min(35rem,calc(100dvh-2rem))]"
    assert html =~ Web.I18n.t("auth.loginRequired", "en")
  end

  test "following another viewer is perceptible and stale follow buttons disappear", %{
    conn: conn,
    code: code
  } do
    analysis_id = "follow-#{System.unique_integer([:positive])}"
    other_id = "follow-other-#{System.unique_integer([:positive])}"
    assert {:ok, _analysis, _revision} = Analyses.create(analysis_id)
    assert {:ok, _other, _revision} = Analyses.create(other_id)
    :ok = Rooms.add_analysis(code, analysis_id)
    :ok = Rooms.add_analysis(code, other_id)

    {:ok, viewer_a, _html} = live(conn, "/rooms/#{code}?a=#{other_id}")
    {:ok, viewer_b, _html} = live(conn, "/rooms/#{code}?a=#{analysis_id}")

    html = render(viewer_a)
    assert has_element?(viewer_a, "button[phx-click='follow-viewer']")

    [followed_id] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("button[phx-click='follow-viewer']")
      |> LazyHTML.attribute("phx-value-participant_id")

    # Following a foreign analysis silently does nothing.
    html =
      render_click(viewer_a, "follow-viewer", %{
        "analysis_id" => "missing",
        "path" => "",
        "participant_id" => followed_id
      })

    refute html =~ "Viewing "

    # The real follow is always perceptible, even when the jump is visible.
    html =
      render_click(viewer_a, "follow-viewer", %{
        "analysis_id" => analysis_id,
        "path" => "",
        "participant_id" => followed_id
      })

    assert html =~ "Viewing "
    assert_patch(viewer_a, "/rooms/#{code}?a=#{analysis_id}")

    # Once the followed analysis leaves the room, no follow button points at it
    # (the surviving viewer re-selects, which is a legitimate button again).
    :ok = Rooms.remove_analysis(code, analysis_id)
    _html = render(viewer_a)

    refute has_element?(
             viewer_a,
             "button[phx-click='follow-viewer'][phx-value-analysis_id='#{analysis_id}']"
           )
  end

  test "the black reply remains on the main line and variations are indented", %{code: code} do
    {:ok, analysis, _revision} = Analyses.create("tree-test")
    :ok = Rooms.add_analysis(code, analysis.id)

    assert {:ok, _analysis, _revision, [0]} =
             Analyses.play(analysis.id, [], Move.new(12, 28))

    assert {:ok, _analysis, _revision, [0, 0]} =
             Analyses.play(analysis.id, [0], Move.new(52, 36))

    assert {:ok, _analysis, _revision, [1]} =
             Analyses.play(analysis.id, [], Move.new(11, 27))

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    entries = AnalysisView.move_entries(analysis, "en")
    black_reply = Enum.find(entries, &(&1.path == [0, 0]))
    white_variation = Enum.find(entries, &(&1.path == [1]))

    assert black_reply.label == "e5"
    assert black_reply.prefix == "1..."
    assert black_reply.depth == 0
    assert white_variation.depth == 1
  end

  test "the move tree pairs mainline moves and nests side lines by branch", %{
    conn: conn,
    code: code
  } do
    {:ok, analysis, _revision} = Analyses.create("paired-tree-test")
    :ok = Rooms.add_analysis(code, analysis.id)

    assert {:ok, _analysis, _revision, [0]} =
             Analyses.play(analysis.id, [], Move.new(11, 27))

    assert {:ok, _analysis, _revision, [0, 0]} =
             Analyses.play(analysis.id, [0], Move.new(51, 35))

    assert {:ok, _analysis, _revision, [0, 0, 0]} =
             Analyses.play(analysis.id, [0, 0], Move.new(6, 21))

    assert {:ok, _analysis, _revision, [0, 0, 0, 0]} =
             Analyses.play(analysis.id, [0, 0, 0], Move.new(62, 45))

    assert {:ok, _analysis, _revision, [0, 0, 0, 1]} =
             Analyses.play(analysis.id, [0, 0, 0], Move.new(54, 46))

    assert {:ok, _analysis, _revision, [0, 0, 0, 1, 0]} =
             Analyses.play(analysis.id, [0, 0, 0, 1], Move.new(10, 26))

    assert {:ok, _analysis, _revision, [0, 0, 0, 1, 1]} =
             Analyses.play(analysis.id, [0, 0, 0, 1], Move.new(1, 18))

    assert {:ok, _analysis, _revision, [0, 0, 0, 1, 0, 0]} =
             Analyses.play(analysis.id, [0, 0, 0, 1, 0], Move.new(35, 26))

    assert {:ok, _analysis, _revision, [0, 0, 0, 1, 0, 1]} =
             Analyses.play(analysis.id, [0, 0, 0, 1, 0], Move.new(52, 44))

    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=#{analysis.id}")
    html = render(view)

    assert [mainline_row] =
             Regex.run(
               ~r/<div[^>]*data-move-row="mainline"[^>]*>(.*?)<\/div>/s,
               html,
               capture: :all_but_first
             )

    assert mainline_row =~ "data-move-path=\"0\""
    assert mainline_row =~ "data-move-path=\"0,0\""
    assert html =~ "data-variation-depth=\"0\""
    assert html =~ "data-variation-depth=\"1\""
    assert html =~ "data-move-path=\"0,0,0,1,1\""
    assert html =~ "0/4"
    assert html =~ "2..."
    assert html =~ "3."
  end

  test "NAGs are saved and rendered on the move", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_hook(element(view, "#chess-board"), "board-move", %{"from" => 12, "to" => 28})
    render_click(view, "toggle-nag", %{"nag" => "1"})
    html = render_click(view, "toggle-nag", %{"nag" => "5"})

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    [first_move] = Node.children(AnalysisModel.root(analysis))
    assert Node.nags(first_move) == [5]

    assert [move_item] =
             Regex.run(~r/<button[^>]*data-move-path="0"[^>]*>(.*?)<\/button>/s, html,
               capture: :all_but_first
             )

    assert move_item =~ "⁉"
    refute move_item =~ "‼"

    # Annotations carry semantic colours: positive good/brilliant, negative
    # mistake/blunder, attention-coloured interesting/dubious.
    for {nag, glyph, css} <- [
          {1, "!", "text-success"},
          {2, "?", "text-error"},
          {3, "‼", "text-success"},
          {4, "⁇", "text-error"},
          {5, "⁉", "text-warning"},
          {6, "⁈", "text-warning"}
        ] do
      html = render_click(view, "toggle-nag", %{"nag" => to_string(nag)})

      assert [move_item] =
               Regex.run(~r/<button[^>]*data-move-path="0"[^>]*>(.*?)<\/button>/s, html,
                 capture: :all_but_first
               )

      assert move_item =~ glyph
      assert move_item =~ css
    end
  end

  test "move-list arrows navigate occurrences and keep one roving tab stop", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_hook(element(view, "#chess-board"), "board-move", %{"from" => 12, "to" => 28})
    render_hook(element(view, "#chess-board"), "board-move", %{"from" => 52, "to" => 36})

    html =
      view
      |> element("#app-shell")
      |> render_hook("move-tree-key", %{"path" => "0,0", "key" => "ArrowLeft"})

    assert html =~ "data-move-path=\"0\""
    assert html =~ "data-move-path=\"0,0\""
    assert html =~ ~r/data-move-path="0"[^>]*tabindex="0"/
    assert html =~ ~r/data-move-path="0,0"[^>]*tabindex="-1"/
  end

  test "move-tree up and down keys rove focus in rendered order without selecting", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_hook(element(view, "#chess-board"), "board-move", %{"from" => 12, "to" => 28})
    render_hook(element(view, "#chess-board"), "board-move", %{"from" => 52, "to" => 36})
    render_click(view, "first-move", %{})

    html =
      view
      |> element("#app-shell")
      |> render_hook("move-tree-key", %{"path" => "0", "key" => "ArrowDown"})

    assert html =~ ~r/data-move-path="0,0"[^>]*tabindex="0"/
    assert html =~ ~r/data-move-path="0"[^>]*tabindex="-1"/
    assert html =~ "0/2"
  end

  test "toggling the engine starts a local analysis that fills the panel and bar", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    # Turning the engine on clears the panel until the local worker reports.
    html = render_click(view, "toggle-engine", %{})

    assert html =~ "role=\"switch\""
    assert html =~ "aria-checked=\"true\""
    assert html =~ "data-engine-on=\"true\""
    assert html =~ "Starting the local engine"
    refute html =~ "data-eval-bar"

    # Throttled UCI info from the worker fills the stats, lines and eval bar.
    html =
      render_click(view, "engine-update", %{
        "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "depth" => 18,
        "nodes" => 612_345,
        "nps" => 450_000,
        "lines" => [
          %{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4 e7e5 g1f3"},
          %{"multipv" => 2, "score_cp" => 10, "pv" => "d2d4 d7d5"}
        ]
      })

    assert html =~ "+0.34"
    assert html =~ "+0.10"
    assert html =~ "612345"
    assert html =~ "450000"

    # Each line is a numbered row of individually clickable moves.
    assert has_element?(
             view,
             "button[phx-click='engine-play-pv'][phx-value-line='1'][phx-value-ply='0']",
             "e4"
           )

    assert has_element?(
             view,
             "button[phx-click='engine-play-pv'][phx-value-line='1'][phx-value-ply='2']",
             "Nf3"
           )

    assert has_element?(
             view,
             "button[phx-click='engine-play-pv'][phx-value-line='2'][phx-value-ply='1']",
             "d5"
           )

    assert html =~ "data-eval-bar"

    # Stale results for another position are dropped; the panel keeps the
    # current evaluation instead of regressing.
    html =
      render_click(view, "engine-update", %{
        "fen" => "8/8/8/8/8/8/8/K6k w - - 0 1",
        "depth" => 30,
        "nodes" => 1,
        "nps" => 1,
        "lines" => [%{"multipv" => 1, "score_cp" => -900, "pv" => "a1a2"}]
      })

    assert html =~ "+0.34"
    refute html =~ "-9.00"
  end

  test "engine scores are white-relative, also when Black is to move", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()
    render_click(view, "toggle-engine", %{})

    # UCI reports from the side to move: +34 with Black to move means Black is
    # slightly better, so the white-relative panel shows a small minus.
    html =
      render_click(view, "engine-update", %{
        "fen" => "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        "depth" => 12,
        "nodes" => 10_000,
        "nps" => 100_000,
        "lines" => [
          %{"multipv" => 1, "score_cp" => 34, "pv" => "e7e5"},
          %{"multipv" => 2, "score_mate" => -3, "pv" => "d7d5"}
        ]
      })

    assert html =~ "-0.34"
    assert html =~ "#3"
  end

  test "clicking a move in an engine line plays the line up to that move", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    render_click(view, "toggle-engine", %{})

    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "depth" => 18,
      "nodes" => 1,
      "nps" => 1,
      "lines" => [
        %{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4 e7e5 g1f3"},
        %{"multipv" => 2, "score_cp" => 10, "pv" => "d2d4 d7d5"}
      ]
    })

    # Clicking the second move of line 1 plays 1.e4 e5 into the tree.
    html = render_click(view, "engine-play-pv", %{"line" => "1", "ply" => "1"})

    assert html =~ "1."
    assert has_element?(view, "button[data-move-path='0']", "e4")
    assert has_element?(view, "button[data-move-path='0,0'][tabindex='0']", "e5")

    # The stale line from before the move is anchored at the old position and
    # does nothing now; only a fresh evaluation may be played.
    refute has_element?(view, "button[data-move-path='1']", "d4")
  end

  test "hovering an engine line move peeks at the position after it", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    render_click(view, "toggle-engine", %{})

    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "depth" => 18,
      "nodes" => 1,
      "nps" => 1,
      "lines" => [%{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4 e7e5"}]
    })

    html = render_click(view, "engine-peek", %{"line" => "1", "ply" => "1"})

    assert html =~ "id=\"engine-peek\""
    assert html =~ "1... e5"

    # The pawn is on e4 in the peek board, not on e2.
    assert html =~ ~r/id="engine-peek".*white_pawn/s

    html = render_click(view, "engine-peek-clear", %{})
    refute html =~ "id=\"engine-peek\""
  end

  test "engine errors surface honestly and switch the engine off", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    # Updates for a switched-off engine never fill the panel.
    html =
      render_click(view, "engine-update", %{
        "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "depth" => 18,
        "nodes" => 1,
        "nps" => 1,
        "lines" => [%{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4"}]
      })

    refute html =~ "+0.34"
    refute html =~ "data-eval-bar"

    render_click(view, "toggle-engine", %{})
    html = render_click(view, "engine-error", %{})

    assert html =~ "The local engine could not start"
    assert html =~ "aria-checked=\"false\""
  end

  test "selected analysis, strip tab, and toolbar icons use the cyan SVG treatment", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    html = render(view)

    assert html =~ "aria-pressed=\"true\""
    assert html =~ "border-highlight/40 bg-highlight/15"
    assert html =~ "border-highlight text-highlight"
    assert html =~ ~r/<button(?=[^>]*aria-label="Edit this position")[^>]*>\s*<svg/s
    assert html =~ ~r/<button(?=[^>]*aria-label="Engine settings")[^>]*>\s*<svg/s
  end

  test "engine settings are available in an honest, session-only popover", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render_click(view, "open-engine-settings", %{})

    assert html =~ "role=\"switch\""
    assert html =~ "aria-checked=\"false\""
    assert html =~ "id=\"engine-provider\""
    assert html =~ "Stockfish 19 (local)"
    assert html =~ "stay in this session"
    assert html =~ "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    html =
      render_change(view, "update-engine-settings", %{
        "depth" => "41",
        "multipv" => "2"
      })

    assert html =~ ~r/name="depth"[^>]*value="40"/
    assert html =~ ~r/name="multipv"[^>]*value="2"/

    html = render_click(view, "toggle-engine", %{})
    assert html =~ "aria-checked=\"true\""
    refute html =~ "id=\"engine-settings-form\""
  end

  test "modal backdrops blur without a dark overlay", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")

    html = render_click(view, "open-shortcuts", %{})

    assert html =~ "backdrop-blur-xs"
    assert html =~ "backdrop-saturate-[.9]"
    refute html =~ "bg-black/60"
  end

  test "board arrows render a filled arrowhead at the destination", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html =
      view
      |> element("#chess-board")
      |> render_hook("board-annotation", %{
        "type" => "arrow",
        "from" => 12,
        "to" => 28,
        "color" => "blue"
      })

    assert html =~ "<polygon points=\""
    assert html =~ "stroke-linecap=\"round\""
    assert html =~ "stroke-width=\"10\""
    refute html =~ "marker-end=\""
  end

  test "piece-set selection switches the board SVG assets", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render_change(view, "set-piece-set", %{"piece_set" => "cburnett"})

    assert html =~ "/images/pieces/cburnett/white_pawn.svg"
  end

  test "open-file layer has a visible marker on the board", %{conn: conn, code: code} do
    position =
      Position.starting_position()
      |> Position.remove_piece(8)
      |> Position.remove_piece(48)

    {:ok, analysis, _revision} = Analyses.create("open-file", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=open-file")

    html = render_click(view, "toggle-layer", %{"layer" => "files"})

    assert html =~ "border-cyan-700/90"
  end

  test "switching locale relocalizes the move tree", %{conn: conn} do
    Application.ensure_all_started(:analysis)
    code = "NL" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    {:ok, analysis, _revision} = Analyses.create("locale-study")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, _analysis, _revision, _path} = Analyses.play(analysis.id, [], Move.new(12, 28))
    {:ok, _analysis, _revision, _path} = Analyses.play(analysis.id, [0], Move.new(52, 36))
    {:ok, _analysis, _revision, _path} = Analyses.play(analysis.id, [0, 0], Move.new(6, 21))

    on_exit(fn -> Rooms.stop_room(code) end)

    {:ok, view, html} = live(conn, "/rooms/#{code}?a=locale-study")
    assert html =~ "Nf3"

    html = render_click(view, "set-locale", %{"locale" => "nl"})
    assert html =~ "Pf3"
  end

  test "opening the setup modal renders a second board", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    html = render_click(view, "open-setup", %{})

    assert html =~ "setup-board"
    assert html =~ "setup-palette"
  end

  test "dropping a palette piece stores a position draft", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render_click(view, "palette-drop", %{"piece" => "white_knight", "square" => "18"})

    assert html =~ "data-pending-edit"
  end

  test "dropping a palette piece in the setup modal places it", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "open-setup", %{})

    html =
      render_click(view, "setup-palette-drop", %{"piece" => "white_knight", "square" => "27"})

    assert html =~ "setup-board"
  end

  test "move buttons no longer round-trip focus", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("no-focus")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, _a, _r, _p} = Analyses.play(analysis.id, [], Move.new(12, 28))

    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=no-focus")

    # A phx-focus round trip on mousedown patches the button mid-click and
    # swallows the click, so the move tree keeps its tabstop client-side.
    refute render(view) =~ ~s(phx-focus="move-tree-focus")
  end

  test "promote is offered only for variations", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("promote-ui")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, _a, _r, _} = Analyses.play(analysis.id, [], Move.new(12, 28))
    {:ok, _a, _r, _} = Analyses.play(analysis.id, [], Move.new(11, 27))

    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=promote-ui")

    html = render_click(view, "select-path", %{"path" => "1"})
    assert html =~ "Promote variation"

    html = render_click(view, "select-path", %{"path" => "0"})
    refute html =~ "Promote variation"
  end

  test "the board renders the arrow-draft hint and documents the arrow keys", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render(view)
    assert html =~ "data-arrow-hint"
    assert html =~ "data-arrow-from"

    html = render_click(view, "open-shortcuts", %{})
    assert html =~ "Start and finish an arrow"
    assert html =~ "Cancel the draft"
    assert html =~ "Previous / next move"
  end

  test "notices expire without clearing newer ones", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html =
      view
      |> element("#chess-board")
      |> render_hook("board-move", %{"from" => 12, "to" => 13})

    assert html =~ "Illegal move"
    first_id = :sys.get_state(view.pid).socket.assigns.notice.id

    # a newer notice replaces it; the older timer must not clear the new one
    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 13})

    second_id = :sys.get_state(view.pid).socket.assigns.notice.id
    assert first_id != second_id

    send(view.pid, {:clear_notice, first_id})
    _ = :sys.get_state(view.pid)
    assert render(view) =~ "Illegal move"

    send(view.pid, {:clear_notice, second_id})
    _ = :sys.get_state(view.pid)
    refute render(view) =~ "Illegal move"
  end

  test "room and setup boards use unique square ids", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    html = render_click(view, "open-setup", %{})

    ids =
      ~r/id="(chess-board-square-[a-h][1-8]|setup-board-square-[a-h][1-8])"/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()

    # duplicate DOM ids across the two boards confuse LiveView's keyed morphing;
    # the main board then loses its squares when the setup modal opens
    assert length(ids) == 128
    assert length(Enum.uniq(ids)) == 128
  end

  test "adjacent highlights share one border", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view
    |> element("#chess-board")
    |> render_hook("board-annotation", %{"type" => "square", "square" => "27", "color" => "blue"})

    html =
      view
      |> element("#chess-board")
      |> render_hook("board-annotation", %{
        "type" => "square",
        "square" => "28",
        "color" => "blue"
      })

    d4 = highlight_style(html, 27)
    e4 = highlight_style(html, 28)

    # d4 + e4: the shared edge is gone, the outer edges remain
    assert d4 =~ "border-left:5px"
    assert d4 =~ "border-top:5px"
    refute d4 =~ "border-right:5px"

    assert e4 =~ "border-right:5px"
    assert e4 =~ "border-bottom:5px"
    refute e4 =~ "border-left:5px"
  end

  defp highlight_style(html, square) do
    case Regex.run(~r/data-highlight-square="#{square}"[^>]*style="([^"]*)"/, html,
           capture: :all_but_first
         ) do
      [style] -> style
      _ -> flunk("no highlight style found for square #{square}")
    end
  end

  defp wait_until_room_unregistered(code, attempts \\ 100)

  defp wait_until_room_unregistered(_code, 0), do: {:error, :room_still_registered}

  defp wait_until_room_unregistered(code, attempts) do
    case Horde.Registry.lookup(Analysis.RoomRegistry, code) do
      [] ->
        :ok

      _workers ->
        Process.sleep(10)
        wait_until_room_unregistered(code, attempts - 1)
    end
  end

  defp room_analysis_id!(code) do
    {:ok, room} =
      Rooms.get(code)

    [analysis_id] =
      Analysis.Room.analysis_ids(room)

    analysis_id
  end
end
