defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Analyses
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

  test "playing moves makes only the required cross-region calls", %{
    conn: conn,
    code: code
  } do
    # Room and analysis processes can live in another Fly region than the
    # LiveView, so every store call is a cross-region round trip. Count them
    # through forwarding proxies and assert a move costs exactly one round
    # trip per store (the mutation itself) and nothing else: no room/analysis
    # re-fetch for the sidebar, no position re-fetch for the board (cache), no
    # self-triggered analysis_changed refresh (the revision is already in
    # hand).
    start_supervised!(Web.CrossRegionCounters)
    start_supervised!(Web.CountingPositionStore)

    Application.put_env(:analysis, Analysis.PositionStore, server: Web.CountingPositionStore)

    Application.put_env(:analysis, Analysis.AnalysisStore, adapter: Web.CountingAnalysisStore)

    on_exit(fn ->
      Application.put_env(:analysis, Analysis.PositionStore, [])
      Application.put_env(:analysis, Analysis.AnalysisStore, [])
    end)

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    analysis_id = room_analysis_id!(code)

    Web.CrossRegionCounters.reset()

    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 12, "to" => 28})

    # render/1 is processed after the self-published analysis_changed message
    # (mailbox order), so a regression to the old full re-fetch shows up here.
    assert render(view) =~ "rev 2"

    assert %{
             "analysis:get" => 1,
             "analysis:update" => 1,
             "position:get" => 1,
             "position:append" => 1
           } = Web.CrossRegionCounters.counts()

    Web.CrossRegionCounters.reset()

    view
    |> element("#chess-board")
    |> render_hook("board-move", %{"from" => 52, "to" => 36})

    assert render(view) =~ "rev 3"

    # Same shape for the second move: the move-list positions and the board
    # render come from the position cache, the sidebar revision is patched
    # locally, and the same-revision analysis_changed is skipped.
    assert %{
             "analysis:get" => 1,
             "analysis:update" => 1,
             "position:get" => 1,
             "position:append" => 1
           } = Web.CrossRegionCounters.counts()

    assert {:ok, analysis, 3} = Analyses.get(analysis_id)
    assert length(AnalysisView.move_entries(analysis, "en")) == 2
  end

  test "an analysis_changed for a newer revision refreshes the view", %{
    conn: conn,
    code: code
  } do
    {:ok, analysis, _revision} = Analyses.create("newer-revision")
    :ok = Rooms.add_analysis(code, analysis.id)

    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=newer-revision")

    # A remote write (another LiveView, another region): the published
    # revision is newer than ours, so the change must be fetched and rendered.
    assert {:ok, _analysis, _revision, _path} =
             Analyses.play(analysis.id, [], Move.new(12, 28))

    send(view.pid, {:analysis_changed, analysis.id, 2})
    _ = :sys.get_state(view.pid)

    html = render(view)
    assert html =~ "occupied by white pawn e4"
    assert html =~ "1/1"
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

  # The Board hook drives optimistic moves from these board attributes: the
  # play-mode flag (server routes square clicks to move playing only when
  # this is set), the side to move and the piece colours. Guards the
  # client/server contract the rapid-move support depends on.
  test "the play board renders the optimistic-move contract attributes", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    html = render_click(view, "create-analysis", %{})

    board =
      ~r/<div[^>]*id="chess-board"[^>]*/
      |> Regex.run(html)
      |> List.first()

    assert board =~ ~s(data-play="")
    assert board =~ ~s(data-side-to-move="white")
    assert html =~ ~s(data-piece-color="white")

    # the setup board keeps its native (non-play) flow
    html = render_click(view, "open-setup", %{})
    setup_board = ~r/<div[^>]*id="setup-board"[^>]*/ |> Regex.run(html) |> List.first()
    refute setup_board =~ "data-play"

    # the editor routes square clicks to editing, not to move playing
    render_click(view, "close-modal", %{})
    render_click(view, "toggle-position-editor", %{})
    html = render_click(view, "arm-piece", %{"piece" => "white_knight"})
    refute html =~ ~s(data-play="")
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

    render_submit(first, "send-chat", %{"message" => "hello from LiveView"})

    assert render(second) =~ "hello from LiveView"
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

  test "a PGN file upload is replayed into a room analysis", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "open-import", %{})

    upload =
      file_input(view, "#pgn-import-form", :pgn, [
        %{
          name: "sample.pgn",
          content: DemoData.game("demo-ruy-lopez").pgn,
          type: "application/x-chess-pgn"
        }
      ])

    render_upload(upload, "sample.pgn")
    render_submit(view, "import-pgn", %{"pgn_text" => ""})

    analysis_id =
      room_analysis_id!(code)

    assert {:ok, analysis, _revision} =
             Analyses.get(analysis_id)

    assert length(AnalysisView.move_entries(analysis, "en")) == 10
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
    assert html =~ "local demo fixtures"
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

  test "engine preview output is visibly labelled as demo data", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render_click(view, "toggle-engine", %{})

    assert html =~ "DEMO"
    assert html =~ "Illustrative fixture only"
    assert html =~ "+0.24"
    assert html =~ "data-eval-bar"
    assert html =~ "role=\"switch\""
    assert html =~ "aria-checked=\"true\""
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
    assert html =~ "Demo fixture"
    assert html =~ "settings stay in this session"
    assert html =~ "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    html =
      render_change(view, "update-engine-settings", %{
        "depth" => "41",
        "movetime_ms" => "500",
        "multipv" => "2"
      })

    assert html =~ ~r/name="depth"[^>]*value="40"/
    assert html =~ ~r/name="movetime_ms"[^>]*value="500"/
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

  defp room_analysis_id!(code) do
    {:ok, room} =
      Rooms.get(code)

    [analysis_id] =
      Analysis.Room.analysis_ids(room)

    analysis_id
  end
end
