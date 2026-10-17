defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Analyses
  alias Analysis.AnalysisStore
  alias Analysis.GameContent
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.ProviderGrants
  alias Analysis.Rooms
  alias Analysis.UserSessions
  alias Analysis.Users
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.Square
  alias OpenChessLab.Repo
  alias Web.AnalysisView
  alias Web.DemoData

  setup do
    Application.ensure_all_started(:analysis)
    code = "LV" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)
    {:ok, code: code}
  end

  test "visiting a room counts as activity for retention", %{conn: conn, code: code} do
    OpenChessLab.Repo.query!(
      "UPDATE rooms SET last_active_at = now() - interval '2 days' WHERE id = $1",
      [code]
    )

    {:ok, _view, _html} = live(conn, "/rooms/#{code}")

    assert Repo.query!(
             "SELECT last_active_at > now() - interval '1 hour' FROM rooms WHERE id = $1",
             [code]
           ).rows == [[true]]
  end

  test "a signed-in user's room presence uses the session name", %{
    conn: conn,
    code: code
  } do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    on_exit(fn -> Users.delete(user.id) end)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_token: session.token})
      |> get("/")

    name = get_session(conn, :display_name)

    {:ok, view, _html} = live(recycle(conn), "/rooms/#{code}")

    # The one identity: presence badge and account badge agree.
    assert has_element?(view, "[title='#{name}']")
    assert has_element?(view, "#account-badge[title='#{name}']")
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
    # Navigation renders instantly; the URL syncs with a trailing debounce.
    assert render(view) =~ ~s(aria-label="occupied by white pawn e2")
    Process.sleep(400)
    assert_patch(view, root_url, 800)

    render_click(view, "next-move", %{})
    assert render(view) =~ ~s(aria-label="occupied by white pawn e4")
    Process.sleep(400)
    assert_patch(view, first_move_url, 800)

    render_click(view, "previous-move", %{})
    assert render(view) =~ ~s(aria-label="occupied by white pawn e2")
    Process.sleep(400)
    assert_patch(view, root_url, 800)

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

  test "game search runs against the real corpus and opens hits in the room", %{
    conn: conn,
    code: code
  } do
    # Structural search modes scan the whole corpus (match-all records), so
    # leftover games from earlier tests fill the first keyset page and push
    # this test's records past it. Give this test its own clean corpus.
    OpenChessLab.Repo.query!(
      "TRUNCATE TABLE game_records, game_occurrences, games, position_features, positions RESTART IDENTITY CASCADE",
      []
    )

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    corpus = seed_search_corpus()

    html =
      view
      |> render_click("open-search", %{})
      |> then(fn _ -> render_submit(view, "search-games", %{"player" => "carlsen"}) end)

    # Real results, no fixtures: the case-insensitive substring matches.
    # Assert on the submitted HTML strings: has_element? reads a proxy tree
    # that can lag a fresh render_submit and flaked here under some seeds.
    refute html =~ "DEMO"
    assert html =~ ~s(id="corpus-#{corpus.carlsen_win}")
    refute html =~ ~s(id="corpus-#{corpus.other_win}")

    # The note states the honest corpus size and each hit previews the
    # matched position.
    assert html =~ "Searches the 4 games"
    assert html =~ "data-mini-board"

    # Colour scoping: the opponent won as Black in the loss record; as White
    # that record no longer matches.
    html =
      render_submit(view, "search-games", %{
        "player" => "opponent",
        "color" => "black",
        "result" => "0-1"
      })

    assert html =~ ~s(id="corpus-#{corpus.carlsen_loss}")

    html =
      render_submit(view, "search-games", %{
        "player" => "opponent",
        "color" => "white",
        "result" => "0-1"
      })

    refute html =~ ~s(id="corpus-#{corpus.carlsen_loss}")

    # Position search: only games that actually reached the position qualify.
    html =
      render_submit(view, "search-games", %{
        "player" => "",
        "color" => "either",
        "result" => "either",
        "fen" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
      })

    assert html =~ ~s(id="corpus-#{corpus.carlsen_win}")
    refute html =~ ~s(id="corpus-#{corpus.carlsen_loss}")
    refute html =~ ~s(id="corpus-#{corpus.transpo}")

    # Structural modes widen honestly: the transposition game shares the pawn
    # structure but not the exact position; the d4/d5 game is a file-reflected
    # pawn symmetry of it.
    html =
      render_submit(view, "search-games", %{
        "fen" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        "position_mode" => "structure"
      })

    assert html =~ ~s(id="corpus-#{corpus.carlsen_win}")
    assert html =~ ~s(id="corpus-#{corpus.transpo}")
    refute html =~ ~s(id="corpus-#{corpus.carlsen_loss}")

    html =
      render_submit(view, "search-games", %{
        "fen" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
        "position_mode" => "structure_symmetries"
      })

    assert html =~ ~s(id="corpus-#{corpus.carlsen_loss}")

    # An unparseable FEN is an honest error, not an empty result set.
    html = render_submit(view, "search-games", %{"fen" => "not a fen"})
    assert html =~ "id=\"search-error\""
    assert html =~ "could not be parsed"

    # A hit opens as a fresh analysis in the room.
    render_submit(view, "search-games", %{"player" => "carlsen"})
    html = render_click(view, "open-corpus-game", %{"id" => corpus.carlsen_win})

    assert {:ok, room} = Analysis.RoomStore.get(code)
    assert length(room.analysis_ids) == 1
    assert html =~ "Added to this room."

    {:ok, analysis, _revision} =
      AnalysisStore.get(hd(room.analysis_ids))

    assert analysis.source_game_record_id == corpus.carlsen_win

    cleanup_search_corpus(corpus)
  end

  test "game search filters by rating and date range", %{conn: conn, code: code} do
    OpenChessLab.Repo.query!(
      "TRUNCATE TABLE game_records, game_occurrences, games, position_features, positions RESTART IDENTITY CASCADE",
      []
    )

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    corpus = seed_search_corpus()
    render_click(view, "open-search", %{})

    # Ratings apply to both players: only "Somebody Else" (2505/2515) sits in
    # the 2500–2520 band (the transposition fails it on Black's 2499).
    html =
      render_submit(view, "search-games", %{
        "rating_min" => "2500",
        "rating_max" => "2520"
      })

    assert html =~ ~s(id="corpus-#{corpus.other_win}")
    refute html =~ ~s(id="corpus-#{corpus.carlsen_win}")
    refute html =~ ~s(id="corpus-#{corpus.transpo}")

    # Dates compare lexicographically in the corpus's YYYY.MM.DD format.
    html =
      render_submit(view, "search-games", %{
        "rating_min" => "",
        "rating_max" => "",
        "date_from" => "2026.09.04",
        "date_to" => "2026.09.06"
      })

    assert html =~ ~s(id="corpus-#{corpus.carlsen_loss}")
    refute html =~ ~s(id="corpus-#{corpus.carlsen_win}")

    cleanup_search_corpus(corpus)
  end

  test "structural search modes find push, missing-pawn and edit neighbors", %{
    conn: conn,
    code: code
  } do
    OpenChessLab.Repo.query!(
      "TRUNCATE TABLE game_records, game_occurrences, games, position_features, positions RESTART IDENTITY CASCADE",
      []
    )

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    start_id = PositionStore.append(Position.starting_position())
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))

    # The search position is after 1.e4 e5.
    {:ok, exact} =
      GameRecords.create(
        "search-exact-#{suffix}",
        GameContent.new(start_id, [corpus_move("e2", "e4"), corpus_move("e7", "e5")]),
        GameStart.standard(),
        %{"white" => "Exact Player", "black" => "Opponent", "result" => "1-0"}
      )

    # One single-rank push away from it, never passing through it: 1.e3 e5.
    {:ok, push} =
      GameRecords.create(
        "search-push-#{suffix}",
        GameContent.new(start_id, [corpus_move("e2", "e3"), corpus_move("e7", "e5")]),
        GameStart.standard(),
        %{"white" => "Push Player", "black" => "Opponent", "result" => "1-0"}
      )

    # One pawn missing from it: after 3.Nxe5 Black's e-pawn is gone.
    {:ok, missing} =
      GameRecords.create(
        "search-missing-#{suffix}",
        GameContent.new(
          start_id,
          [
            corpus_move("e2", "e4"),
            corpus_move("e7", "e5"),
            corpus_move("g1", "f3"),
            corpus_move("b8", "c6"),
            corpus_move("f3", "e5")
          ]
        ),
        GameStart.standard(),
        %{"white" => "Missing Player", "black" => "Opponent", "result" => "0-1"}
      )

    fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    render_click(view, "open-search", %{})

    html = render_submit(view, "search-games", %{"fen" => fen})
    assert html =~ ~s(id="corpus-#{exact.id}")
    refute html =~ ~s(id="corpus-#{push.id}")

    # The push neighbor never shares the structure; single-push finds it.
    html =
      render_submit(view, "search-games", %{"fen" => fen, "position_mode" => "structure_push"})

    assert html =~ ~s(id="corpus-#{push.id}")
    assert html =~ ~s(id="corpus-#{exact.id}")

    # Missing-pawn and edit-distance-1 modes find their neighborhoods.
    html =
      render_submit(view, "search-games", %{"fen" => fen, "position_mode" => "structure_missing"})

    assert html =~ ~s(id="corpus-#{missing.id}")

    html =
      render_submit(view, "search-games", %{"fen" => fen, "position_mode" => "structure_edit1"})

    assert html =~ ~s(id="corpus-#{push.id}")
    assert html =~ ~s(id="corpus-#{missing.id}")

    # The remaining modes at least run cleanly against the corpus.
    for mode <- ["structure_color_reversed", "structure_reflected"] do
      html = render_submit(view, "search-games", %{"fen" => fen, "position_mode" => mode})
      refute html =~ "id=\"search-error\""
    end
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

    # The chat form lives in the drawer; opening it renders the form and
    # clears the unread badge.
    render_click(first, "open-chat", %{})
    render_click(second, "open-chat", %{})
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
            content: "1. e4! {Uploaded note} e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 *",
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
    assert hd(analysis.root.children).comment == "Uploaded note"
    assert hd(analysis.root.children).nags == [1]

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

  describe "multi-source game import" do
    setup do
      original = Application.fetch_env(:web, :game_import_request)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:web, :game_import_request, value)
          :error -> Application.delete_env(:web, :game_import_request)
        end
      end)

      :ok
    end

    test "imports several pasted games at once", %{conn: conn, code: code} do
      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      render_submit(view, "import-pgn", %{
        "pgn_text" => "[Event \"A\"]\n\n1. e4 e5 1-0\n\n[Event \"B\"]\n\n1. d4 d5 *\n"
      })

      assert length(room_analysis_ids(code)) == 2
      refute has_element?(view, "#import-skips")
    end

    test "fetches Lichess URLs mixed with pasted PGN", %{conn: conn, code: code} do
      stub_game_import([
        {200, "[Event \"L\"]\n[Site \"https://lichess.org/LhL9TRJY\"]\n\n1. c4 e5 *\n"}
      ])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      render_submit(view, "import-pgn", %{
        "pgn_text" => "1. e4 e5 *\nhttps://lichess.org/LhL9TRJY\n"
      })

      assert length(room_analysis_ids(code)) == 2
      refute has_element?(view, "#import-skips")
    end

    test "missing Lichess ids become skips and the dialog stays open", %{
      conn: conn,
      code: code
    } do
      stub_game_import([
        {200, "[Event \"L\"]\n[Site \"https://lichess.org/LhL9TRJY\"]\n\n1. c4 e5 *\n"}
      ])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      render_submit(view, "import-pgn", %{
        "pgn_text" => "https://lichess.org/LhL9TRJY\nhttps://lichess.org/ZZZZZZZZ\n"
      })

      assert length(room_analysis_ids(code)) == 1
      assert has_element?(view, "#import-skips", "lichess.org/ZZZZZZZZ")
      assert has_element?(view, "#import-title")
    end

    test "a Chess.com URL is skipped with an honest reason", %{conn: conn, code: code} do
      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      render_submit(view, "import-pgn", %{
        "pgn_text" => "https://www.chess.com/game/live/123\n"
      })

      assert room_analysis_ids(code) == []
      assert has_element?(view, "#import-skips", "Chess.com links cannot be fetched")
    end

    test "the Lichess tray lists recent games and imports the selection", %{
      conn: conn,
      code: code
    } do
      metadata =
        Enum.map_join(
          [
            %{
              "id" => "LhL9TRJY",
              "speed" => "blitz",
              "winner" => "white",
              "lastMoveAt" => 1_700_000_000_000,
              "players" => %{
                "white" => %{"user" => %{"name" => "Anna"}},
                "black" => %{"user" => %{"name" => "Boris"}}
              }
            },
            %{
              "id" => "PndlSDZg",
              "speed" => "rapid",
              "winner" => "black",
              "lastMoveAt" => 1_699_000_000_000,
              "players" => %{
                "white" => %{"user" => %{"name" => "Cleo"}},
                "black" => %{"user" => %{"name" => "Anna"}}
              }
            }
          ],
          "\n",
          &Jason.encode!/1
        )

      stub_game_import([
        {200, metadata <> "\n"},
        {200, "[Event \"A\"]\n[Site \"https://lichess.org/LhL9TRJY\"]\n\n1. e4 e5 *\n"}
      ])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "lichess"})

      render_submit(view, "load-provider-games", %{
        "provider" => "lichess",
        "username" => "anna"
      })

      assert has_element?(view, "#import-games-tray", "Anna – Boris")
      assert has_element?(view, "#import-games-tray", "Cleo – Anna")
      assert has_element?(view, "#import-selected", "Import 2 games")

      # Deselecting one updates the count-aware button.
      render_click(view, "toggle-import-game", %{"id" => "PndlSDZg"})
      assert has_element?(view, "#import-selected", "Import 1 game")
      render_click(view, "select-all-import-games", %{})
      assert has_element?(view, "#import-selected", "Import 2 games")

      # The deselected game is fetched too, but comes back missing: an
      # honest skip, and the dialog stays open to show it.
      render_click(view, "toggle-import-game", %{"id" => "PndlSDZg"})
      render_click(view, "import-selected-games", %{})

      assert length(room_analysis_ids(code)) == 1
    end

    test "a selected Lichess game that does not come back is an honest skip", %{
      conn: conn,
      code: code
    } do
      metadata =
        Jason.encode!(%{
          "id" => "ZZZZZZZZ",
          "speed" => "blitz",
          "lastMoveAt" => 1_700_000_000_000,
          "players" => %{
            "white" => %{"user" => %{"name" => "Anna"}},
            "black" => %{"user" => %{"name" => "Boris"}}
          }
        })

      stub_game_import([
        {200, metadata <> "\n"},
        {200, ""}
      ])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "lichess"})

      render_submit(view, "load-provider-games", %{
        "provider" => "lichess",
        "username" => "anna"
      })

      render_click(view, "import-selected-games", %{})

      assert room_analysis_ids(code) == []
      assert has_element?(view, "#import-skips", "lichess.org/ZZZZZZZZ")
    end

    test "an unknown Lichess account shows an honest error", %{conn: conn, code: code} do
      stub_game_import([{404, ""}])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "lichess"})

      html =
        render_submit(view, "load-provider-games", %{
          "provider" => "lichess",
          "username" => "nobody"
        })

      assert html =~ "Account not found."
      refute has_element?(view, "#import-games-tray")
      assert room_analysis_ids(code) == []
    end

    test "the Chess.com tray imports the selection without refetching", %{
      conn: conn,
      code: code
    } do
      month = %{
        "games" => [
          %{
            "url" => "https://www.chess.com/game/live/111",
            "pgn" => "[Event \"A\"]\n\n1. e4 e5 *",
            "time_class" => "blitz",
            "end_time" => 1_700_000_000,
            "white" => %{"username" => "anna", "result" => "win"},
            "black" => %{"username" => "boris", "result" => "resigned"}
          },
          %{
            "url" => "https://www.chess.com/game/live/222",
            "pgn" => "[Event \"B\"]\n\n1. d4 d5 *",
            "time_class" => "rapid",
            "end_time" => 1_699_000_000,
            "white" => %{"username" => "cleo", "result" => "agreed"},
            "black" => %{"username" => "anna", "result" => "agreed"}
          }
        ]
      }

      # One response only: a refetch on import would crash the stub.
      stub_game_import([{200, Jason.encode!(month)}])

      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "chesscom"})

      render_submit(view, "load-provider-games", %{
        "provider" => "chesscom",
        "username" => "anna",
        "month" => "2023-11"
      })

      assert has_element?(view, "#import-games-tray", "anna – boris")
      render_click(view, "import-selected-games", %{})

      assert length(room_analysis_ids(code)) == 2
    end

    test "a broken Chess.com month is an honest error", %{conn: conn, code: code} do
      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "chesscom"})

      html =
        render_submit(view, "load-provider-games", %{
          "provider" => "chesscom",
          "username" => "someone",
          "month" => "bogus"
        })

      assert html =~ "Pick a valid month."
      refute has_element?(view, "#import-games-tray")
    end
  end

  describe "import keep options" do
    test "the dialog offers the four keep options with honest defaults", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      assert has_element?(view, "#import-keep-comments[checked]")
      assert has_element?(view, "#import-keep-variations[checked]")
      assert has_element?(view, "#import-keep-metadata[checked]")
      refute has_element?(view, "#import-keep-annotations[checked]")
    end

    test "unchecked variations and comments are dropped from the import", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      render_click(view, "toggle-import-keep", %{"key" => "variations"})
      render_click(view, "toggle-import-keep", %{"key" => "comments"})

      render_submit(view, "import-pgn", %{
        "pgn_text" => "[Event \"A\"]\n\n1. e4 e5 {the note} (1... c5) 2. Nf3 Nc6 *"
      })

      analysis_id = room_analysis_id!(code)
      assert {:ok, analysis, _revision} = Analyses.get(analysis_id)

      [e4] = analysis.root.children
      [e5] = e4.children
      assert e5.comment == nil
      assert [nf3] = e5.children
      assert [_nc6] = nf3.children
    end

    test "engine annotations land on the nodes only when asked", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})

      annotated = "[Event \"A\"]\n\n1. e4 {[%clk 0:05:00] [%eval 0.20]} e5 *"

      render_submit(view, "import-pgn", %{"pgn_text" => annotated})

      analysis_id = room_analysis_id!(code)
      assert {:ok, analysis, _revision} = Analyses.get(analysis_id)
      [e4] = analysis.root.children
      assert e4.clock == nil
      assert e4.evaluation == nil

      render_click(view, "open-import", %{})
      render_click(view, "toggle-import-keep", %{"key" => "annotations"})
      render_submit(view, "import-pgn", %{"pgn_text" => annotated})

      [first_id, second_id] = room_analysis_ids(code)
      assert {:ok, _first, _} = Analyses.get(first_id)
      assert {:ok, second, _} = Analyses.get(second_id)
      [e4] = second.root.children
      assert e4.clock == "0:05:00"
      assert e4.evaluation == "0.20"
      # Annotations never leak into the human comment text.
      assert e4.comment == nil
    end
  end

  describe "linked-account import" do
    setup do
      original = Application.fetch_env(:web, :game_import_request)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:web, :game_import_request, value)
          :error -> Application.delete_env(:web, :game_import_request)
        end
      end)

      {:ok, user} = Users.create()
      {:ok, session} = UserSessions.create(user.id)
      on_exit(fn -> Users.delete(user.id) end)
      %{user: user, session: session}
    end

    test "a linked account prefills the Lichess username from the grant", %{
      conn: conn,
      code: code,
      user: user,
      session: session
    } do
      :ok = ProviderGrants.put(user.id, "lichess", "lip_test_token")

      stub_game_import([
        {200, Jason.encode!(%{"username" => "linkeduser"})}
      ])

      conn = Plug.Test.init_test_session(conn, %{user_token: session.token})
      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      render_click(view, "set-import-source", %{"source" => "lichess"})

      assert has_element?(view, "#provider-username[value='linkeduser']")
    end

    test "a rejected grant token deletes the grant honestly", %{
      conn: conn,
      code: code,
      user: user,
      session: session
    } do
      :ok = ProviderGrants.put(user.id, "lichess", "lip_revoked_token")
      stub_game_import([{401, ""}])

      conn = Plug.Test.init_test_session(conn, %{user_token: session.token})
      {:ok, view, _} = live(conn, "/rooms/#{code}")
      render_click(view, "open-import", %{})
      html = render_click(view, "set-import-source", %{"source" => "lichess"})

      assert html =~ "expired"
      refute ProviderGrants.has?(user.id, "lichess")
    end
  end

  test "the room bar carries the analysis chips and the chat button", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    html = render(view)

    # The old sidebar drawer scheme is gone.
    refute html =~ ~s(phx-hook="RoomTabs")
    refute html =~ "data-tab="
    refute html =~ "data-mobile-panel"

    # The bar holds the chips, their actions and the chat button.
    assert html =~ ~s(id="room-bar")
    assert html =~ ~s(data-tour="analyses")
    assert html =~ "analysis-chip-"
    assert html =~ ~s(id="chat-open")
    refute html =~ ~s(id="chat-drawer")

    # Opening the chat button reveals the drawer with the log and the form.
    html = render_click(view, "open-chat", %{})
    assert html =~ ~s(id="chat-drawer")
    assert html =~ ~s(id="chat-log")
    assert html =~ ~s(id="chat-message")

    html = render_click(view, "close-chat", %{})
    refute html =~ ~s(id="chat-drawer")
  end

  test "removing the active analysis asks first and deletes it when unreferenced", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "create-analysis", %{})
    [first_id, second_id] = room_analysis_ids(code)

    render_click(view, "select-analysis", %{"id" => first_id})
    html = render(view)

    # Only the active chip carries the remove control.
    assert html =~ ~s(id="remove-#{first_id}")
    refute html =~ ~s(id="remove-#{second_id}")

    # The × opens a confirmation dialog without touching the room.
    html = render_click(view, "request-remove-analysis", %{"id" => first_id})
    assert html =~ ~s(id="remove-analysis-confirm")
    assert room_analysis_ids(code) == [first_id, second_id]

    html = render_click(view, "remove-analysis", %{})
    refute html =~ ~s(id="analysis-chip-#{first_id}")
    assert room_analysis_ids(code) == [second_id]
    # Nothing references it any more, so the aggregate went with it.
    assert :not_found = AnalysisStore.get(first_id)
    # The remaining analysis becomes active and offers its own remove control.
    assert html =~ ~s(id="remove-#{second_id}")

    render_click(view, "request-remove-analysis", %{"id" => second_id})
    html = render_click(view, "remove-analysis", %{})
    assert room_analysis_ids(code) == []
    assert :not_found = AnalysisStore.get(second_id)
    assert html =~ "No analyses in this room yet"
  end

  test "chat messages raise the unread badge while the drawer is closed", %{
    conn: conn,
    code: code
  } do
    {:ok, first, _html} = live(conn, "/rooms/#{code}")
    {:ok, second, _html} = live(build_conn(), "/rooms/#{code}")

    render_click(second, "open-chat", %{})
    render_submit(second, "send-chat", %{"message" => "ping"})

    # The first viewer never opened the drawer: badge above the chat button.
    html = render(first)
    assert html =~ ~s(id="chat-unread")

    # Opening the drawer clears it.
    html = render_click(first, "open-chat", %{})
    refute html =~ ~s(id="chat-unread")
  end

  test "pasted FEN game retains annotations in the ordinary room editor", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _} = live(conn, "/rooms/#{code}")
    render_click(view, "open-import", %{})

    render_submit(view, "import-pgn", %{
      "pgn_text" => """
      [SetUp "1"]
      [FEN "4k3/8/8/8/8/8/4K3/7R b - - 12 37"]

      37... Kf7! {Human note [%eval 0.2]} 38. Rh2 *
      """
    })

    assert {:ok, analysis, _} = Analyses.get(room_analysis_id!(code))
    assert analysis.start == Analysis.GameStart.new(37)
    assert hd(analysis.root.children).nags == [1]
    html = render(view)
    assert html =~ "Human note"
    refute html =~ "[%eval"
    assert render_click(view, "last-move", %{}) =~ "occupied by white rook h2"
  end

  test "the import dialog keeps one height when switching source tabs", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    html = render_click(view, "open-import", %{})

    assert html =~ "h-[min(35rem,calc(100dvh_-_2rem))]"

    html = render_click(view, "set-import-source", %{"source" => "library"})
    assert html =~ "h-[min(35rem,calc(100dvh_-_2rem))]"
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
    {:ok, _viewer_b, _html} = live(conn, "/rooms/#{code}?a=#{analysis_id}")

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
    assert html =~ "Analyzing"

    # The bar stays put while the engine computes: neutral and dimmed, so
    # nothing flickers when the first evaluation lands.
    assert html =~ "data-eval-bar"
    assert html =~ "Evaluation bar —"

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

    # The best move of the top line shows as a green arrow on the board.
    assert html =~ "data-shape-key=\"arrow-12-28-engine\""

    # The arrow follows the position: after 1.e4 the stale line drops it until
    # a fresh evaluation arrives for the new position.
    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()
    refute render(view) =~ "data-shape-key=\"arrow-12-28-engine\""

    html =
      render_click(view, "engine-update", %{
        "fen" => "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        "depth" => 18,
        "nodes" => 1,
        "nps" => 1,
        "lines" => [%{"multipv" => 1, "score_cp" => 20, "pv" => "e7e5"}]
      })

    assert html =~ "data-shape-key=\"arrow-52-36-engine\""

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

    assert html =~ "-0.20"
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

  test "evaluated positions fill the evaluation graph, and it navigates", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    render_click(view, "toggle-engine", %{})

    # No graph until the first evaluation lands.
    refute render(view) =~ "id=\"engine-graph\""

    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "depth" => 14,
      "nodes" => 1,
      "nps" => 1,
      "lines" => [%{"multipv" => 1, "score_cp" => 30, "pv" => "e2e4"}]
    })

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()

    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
      "depth" => 14,
      "nodes" => 1,
      "nps" => 1,
      "lines" => [%{"multipv" => 1, "score_cp" => -15, "pv" => "e7e5"}]
    })

    html = render(view)

    # Two consecutive plies evaluated: one dot each, connected by a polyline.
    assert html =~ "id=\"engine-graph\""
    assert html =~ "<polyline"
    assert html =~ ~r/<circle[^>]*>.*?<\/circle>/s

    # Clicking a graph column navigates: back to the root position.
    html = render_click(view, "select-path", %{"path" => ""})
    assert html =~ "data-fen=\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\""
    assert html =~ "id=\"engine-graph\""
  end

  test "a game review walks the mainline and marks the big swings", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()
    view |> element("#chess-board-square-e7") |> render_click()
    view |> element("#chess-board-square-e5") |> render_click()

    # Starting a review points the worker at the root position.
    html = render_click(view, "engine-review-start", %{})

    assert html =~ "Reviewing"
    assert html =~ "0/3"
    assert html =~ "data-review-fen=\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\""

    # Out-of-order results are ignored.
    render_click(view, "engine-review-result", %{"ply" => "2", "cp" => 10})
    assert render(view) =~ "0/3"

    # Root and 1.e4 stay roughly equal; 1...e5 runs into mate for White.
    # (Engine scores arrive UCI-relative to the side to move; the review
    # stores them white-relative before classifying by Win% drop.)
    render_click(view, "engine-review-result", %{"ply" => "0", "cp" => 30})
    assert render(view) =~ "1/3"
    refute render(view) =~ "data-review-fen=\"\""

    render_click(view, "engine-review-result", %{"ply" => "1", "cp" => -50})
    render_click(view, "engine-review-result", %{"ply" => "2", "mate" => 4})

    html = render(view)

    assert html =~ "Review complete"
    assert html =~ "1 blunders"

    # The summary shows per-side accuracy; Black ran into mate here.
    [_, white_acc, black_acc] = Regex.run(~r/Accuracy: White (\d+)% · Black (\d+)%/, html)
    assert String.to_integer(white_acc) > String.to_integer(black_acc)
    assert html =~ "e5"
    assert html =~ "??"

    # The blunder dot is marked on the graph; the review offers to run again.
    assert html =~ "var(--error)"
    assert has_element?(view, "#engine-review-again")
    assert html =~ "data-review-fen=\"\""

    # The move list carries the mark as well, with the swing in the tooltip.
    assert has_element?(view, "#move-list span.text-error[title*='Blunder']", "??")

    # A stale result after completion changes nothing.
    html = render_click(view, "engine-review-result", %{"ply" => "0", "cp" => -900})
    assert html =~ "1 blunders"
    refute html =~ "-9.00"

    # A fresh run clears the old marks while it recomputes.
    html = render_click(view, "engine-review-start", %{})
    refute has_element?(view, "#move-list span.text-error", "??")
  end

  test "switching analyses cancels a running review", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()

    render_click(view, "engine-review-start", %{})
    assert render(view) =~ "Reviewing"

    # Creating (and selecting) another analysis discards the old review —
    # the worker must not keep evaluating the new game from the old ply.
    render_click(view, "create-analysis", %{})
    html = render(view)
    refute html =~ "Reviewing"
    refute html =~ "engine-review-cancel"

    # With moves on the new game, the panel offers a fresh review.
    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()
    assert has_element?(view, "#engine-review-start")
  end

  test "a finished review does not bleed into another analysis", %{conn: conn, code: code} do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()

    render_click(view, "engine-review-start", %{})
    render_click(view, "engine-review-result", %{"ply" => "0", "cp" => 30})
    render_click(view, "engine-review-result", %{"ply" => "1", "cp" => -50})
    render_click(view, "engine-review-result", %{"ply" => "2", "mate" => 4})

    assert render(view) =~ "Review complete"

    render_click(view, "create-analysis", %{})
    html = render(view)
    refute html =~ "Review complete"
    refute html =~ "review-accuracy"
  end

  test "editing the tree mid-review cancels the review instead of stalling it", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()

    render_click(view, "engine-review-start", %{})
    assert render(view) =~ "Reviewing"

    # Playing a move during the review edits the tree; the review must cancel
    # honestly rather than hang on the stale revision forever.
    view |> element("#chess-board-square-e7") |> render_click()
    view |> element("#chess-board-square-e5") |> render_click()

    html = render_click(view, "engine-review-result", %{"ply" => "0", "cp" => 30})

    assert html =~ "Review cancelled"
    assert html =~ "data-review-fen=\"\""
    assert has_element?(view, "#engine-review-start")
    refute html =~ "Reviewing"
  end

  test "review classification is position-independent, unlike raw centipawns", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()
    render_click(view, "engine-review-start", %{})

    # A 300cp swing from an already-won position (+800 → +500) is a raw-cp
    # blunder but barely moves the win probability (95.4% → 84.7%), so the
    # Win% model rightly marks nothing.
    render_click(view, "engine-review-result", %{"ply" => "0", "cp" => 800})
    render_click(view, "engine-review-result", %{"ply" => "1", "cp" => -500})

    html = render(view)

    assert html =~ "Review complete"
    assert html =~ "0 blunders"
    assert html =~ "0 mistakes"
    assert html =~ "0 inaccuracies"
  end

  test "a cached evaluation fills the panel instantly, no local compute needed", %{
    conn: conn,
    code: code
  } do
    position_id = PositionStore.append(Position.starting_position())
    # Other tests share the canonical start position; start from a clean row.
    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])

    :ok =
      Analysis.PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 20,
        eval_cp: 42,
        mate: nil,
        best_move: "e2e4",
        pv: "e2e4 e7e5",
        nodes: 999_999,
        multipv: 3,
        lines: [
          %{"multipv" => 1, "score_cp" => 42, "pv" => "e2e4 e7e5"},
          %{"multipv" => 2, "score_cp" => 20, "pv" => "d2d4 d7d5"},
          %{"multipv" => 3, "score_cp" => 11, "pv" => "g1f3"}
        ]
      })

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    html = render_click(view, "toggle-engine", %{})

    # No engine-update round trip: the panel and bar come from the cache.
    assert html =~ "+0.42"
    assert html =~ "999999"
    assert html =~ "data-cached-depth=\"20\""
    assert html =~ "data-eval-bar"

    # A shallower cached result does not cover the requested depth. (The
    # deepest-wins upsert refuses to downgrade, so clear the row first.)
    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])

    :ok =
      Analysis.PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 12,
        eval_cp: 10
      })

    # The room now has an analysis, so a fresh visit redirects to it.
    analysis_id = room_analysis_id!(code)
    {:ok, view2, _html} = live(build_conn(), "/rooms/#{code}?a=#{analysis_id}")

    # Default depth is 20; the depth-12 cache must not masquerade as coverage.
    assert render_click(view2, "toggle-engine", %{}) =~ "Analyzing"

    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])
  end

  test "a move never shows a stale evaluation: analyzing state until fresh results", %{
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
      "lines" => [%{"multipv" => 1, "score_cp" => 30, "pv" => "e2e4"}]
    })

    assert render(view) =~ "+0.30"

    # Playing 1.e4 clears the old evaluation immediately; the panel shows the
    # honest analyzing state until the worker reports on the new position.
    view |> element("#chess-board-square-e2") |> render_click()
    html = view |> element("#chess-board-square-e4") |> render_click()

    refute has_element?(view, "#engine-eval")
    assert html =~ "Analyzing"

    # The bar stays visible but neutral and dimmed: no stale score, no flicker.
    # (The graph keeps the root's +0.30 — that is per-position history, not
    # a stale panel evaluation.)
    assert html =~ "data-eval-bar"
    assert html =~ "Evaluation bar —"
    refute html =~ "Evaluation bar +0.30"

    # Fresh results for the new position take over. (Black to move: UCI +12
    # means Black is slightly better, so the white-relative panel shows minus.)
    html =
      render_click(view, "engine-update", %{
        "fen" => "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        "depth" => 18,
        "nodes" => 1,
        "nps" => 1,
        "lines" => [%{"multipv" => 1, "score_cp" => 12, "pv" => "e7e5"}]
      })

    assert html =~ "-0.12"
  end

  test "navigating to a cached position shows its evaluation without a worker round trip", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    view |> element("#chess-board-square-e2") |> render_click()
    view |> element("#chess-board-square-e4") |> render_click()

    position_id = PositionStore.append(Position.starting_position())
    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])

    :ok =
      Analysis.PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 20,
        eval_cp: 37,
        best_move: "e2e4",
        pv: "e2e4 e7e5",
        multipv: 3,
        lines: [
          %{"multipv" => 1, "score_cp" => 37, "pv" => "e2e4 e7e5"},
          %{"multipv" => 2, "score_cp" => 20, "pv" => "d2d4 d7d5"},
          %{"multipv" => 3, "score_cp" => 11, "pv" => "g1f3"}
        ]
      })

    # The engine turns on after the move: no cache there, so it analyzes.
    render_click(view, "toggle-engine", %{})
    assert render(view) =~ "Analyzing"

    # Navigating back to the root shows the cached evaluation instantly.
    html = render_click(view, "select-path", %{"path" => ""})

    assert html =~ "+0.37"
    refute html =~ "Analyzing"

    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])
  end

  test "a finished search persists the evaluation for the whole corpus", %{
    conn: conn,
    code: code
  } do
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})
    render_click(view, "toggle-engine", %{})

    position_id = PositionStore.append(Position.starting_position())
    # The canonical start position is shared; start from a clean cache row.
    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])

    # Intermediate updates never persist.
    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "depth" => 8,
      "nodes" => 1,
      "nps" => 1,
      "lines" => [%{"multipv" => 1, "score_cp" => 20, "pv" => "e2e4"}]
    })

    assert :not_found = Analysis.PositionEvals.get(position_id, "stockfish-19-lite-single")

    render_click(view, "engine-update", %{
      "fen" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "depth" => 20,
      "nodes" => 612_345,
      "nps" => 1,
      "final" => true,
      "lines" => [%{"multipv" => 1, "score_cp" => 34, "pv" => "e2e4 e7e5"}]
    })

    assert {:ok, cached} = Analysis.PositionEvals.get(position_id, "stockfish-19-lite-single")
    assert cached.depth == 20
    assert cached.eval_cp == 34
    assert cached.best_move == "e2e4"

    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])
  end

  test "settings stay effective over a cached evaluation on both axes", %{
    conn: conn,
    code: code
  } do
    position_id = PositionStore.append(Position.starting_position())
    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])

    :ok =
      Analysis.PositionEvals.put(position_id, "stockfish-19-lite-single", %{
        depth: 20,
        eval_cp: 37,
        best_move: "e2e4",
        pv: "e2e4 e7e5",
        multipv: 3,
        lines: [
          %{"multipv" => 1, "score_cp" => 37, "pv" => "e2e4 e7e5"},
          %{"multipv" => 2, "score_cp" => 20, "pv" => "d2d4 d7d5"},
          %{"multipv" => 3, "score_cp" => 11, "pv" => "g1f3"}
        ]
      })

    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    # The cache covers the defaults: all three lines show instantly.
    html = render_click(view, "toggle-engine", %{})
    assert html =~ "+0.37"
    assert html =~ "data-cached-depth=\"20\""
    assert html =~ "data-cached-multipv=\"3\""
    assert has_element?(view, "#engine-panel ol li button", "Nf3")

    # Fewer lines is served from the same cache: the third line leaves.
    html =
      render_change(view, "update-engine-settings", %{
        "depth" => "10",
        "multipv" => "2"
      })

    refute has_element?(view, "#engine-panel ol li button", "Nf3")
    assert has_element?(view, "#engine-panel ol li button[phx-value-line='2']", "d4")

    # An uncovered combination (more lines than cached) keeps showing the
    # cached lines while the hook recomputes: the coverage attribute is what
    # drives the worker restart.
    html =
      render_change(view, "update-engine-settings", %{
        "depth" => "10",
        "multipv" => "5"
      })

    assert html =~ "data-cached-multipv=\"3\""
    assert has_element?(view, "#engine-panel ol li button[phx-value-line='2']", "d4")

    Repo.query!("DELETE FROM position_evals WHERE position_id = $1", [position_id])
  end

  test "the book tab shows corpus moves with ECO classification and plays them", %{
    conn: conn,
    code: code
  } do
    corpus = seed_search_corpus()
    {:ok, view, _html} = live(conn, "/rooms/#{code}")
    render_click(view, "create-analysis", %{})

    # The reference panel loads asynchronously with the corpus moves for the
    # starting position: 1.e4 in two games, 1.d4 and 1.Nf3 in one each.
    render_async(view, 1_000)

    refute has_element?(view, "#book-opening")

    assert has_element?(view, "#book-moves button[phx-value-uci='e2e4']", "e4")
    assert has_element?(view, "#book-moves button[phx-value-uci='d2d4']", "d4")
    assert has_element?(view, "#book-moves button[phx-value-uci='g1f3']", "Nf3")

    # Playing a book move plays it into the analysis.
    render_click(view, "book-play-move", %{"uci" => "e2e4"})
    assert has_element?(view, "#move-list button[data-move-path='0']", "e4")

    # After 1.e4 the panel names the King's Pawn Game and follows the move.
    render_async(view, 1_000)
    assert has_element?(view, "#book-opening", "King's Pawn Game")
    assert has_element?(view, "#book-opening", "B00")

    cleanup_search_corpus(corpus)
  end

  describe "endgame table" do
    setup do
      # Tablebase results are durable; tests must start from an empty cache.
      Repo.query!("TRUNCATE TABLE position_tablebases", [])

      original = Application.fetch_env(:web, :tablebase_request)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:web, :tablebase_request, value)
          :error -> Application.delete_env(:web, :tablebase_request)
        end
      end)

      :ok
    end

    test "the endgame tab shows the tablebase result, caches it and plays moves", %{
      conn: conn,
      code: code
    } do
      stub_tablebase([
        {200,
         ~s({"category":"win","dtz":3,"dtm":7,"moves":[) <>
           ~s({"uci":"d1d8","san":"Qd8+","category":"loss","dtz":-2},) <>
           ~s({"uci":"d1d2","san":"Qd2","category":"draw","dtz":0}]})},
        {200,
         ~s({"category":"loss","dtz":-2,"dtm":-6,"moves":[) <>
           ~s({"uci":"e8d7","san":"Kd7","category":"win","dtz":2}]})}
      ])

      {:ok, view, _html} = live(conn, "/rooms/#{code}")

      # Build a king-and-queen versus king position through the setup modal:
      # e1 = 4, d1 = 3, e8 = 60.
      render_click(view, "open-setup", %{})
      render_click(view, "setup-clear-board", %{})
      render_click(view, "setup-palette-drop", %{"piece" => "white_king", "square" => "4"})
      render_click(view, "setup-palette-drop", %{"piece" => "white_queen", "square" => "3"})
      render_click(view, "setup-palette-drop", %{"piece" => "black_king", "square" => "60"})
      render_click(view, "create-from-setup", %{})

      # In tablebase range the reference panel switches to the exact result.
      render_async(view, 1_000)

      assert has_element?(view, "#endgame-headline", "White wins")
      assert has_element?(view, "#endgame-headline", "Mate in 7")
      assert has_element?(view, "#endgame-moves button[phx-value-uci='d1d8']", "Qd8+")
      # The chip inverts the API's perspective: a loss for the next side to
      # move is a win for the player who plays the move.
      assert has_element?(view, "#endgame-moves li", "Win")

      # Playing a table move plays it into the analysis; the new position is
      # fetched once and again reported from the side to move's perspective.
      render_click(view, "endgame-play-move", %{"uci" => "d1d8"})
      assert has_element?(view, "#move-list button[data-move-path='0']", "Qd8+")
      render_async(view, 1_000)
      assert has_element?(view, "#endgame-headline", "Black loses")
      assert has_element?(view, "#endgame-headline", "Mated in 6")
    end

    test "positions outside the tablebase range skip the fetch", %{
      conn: conn,
      code: code
    } do
      agent =
        stub_tablebase([
          {200, ~s({"category":"draw","moves":[]})}
        ])

      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "create-analysis", %{})
      render_async(view, 1_000)

      # Thirty-two pieces: the panel stays on the corpus side.
      refute has_element?(view, "#endgame-result")
      # The stub was never consumed: no external request was made.
      assert Agent.get(agent, & &1) != []
    end

    test "an unreachable table is reported honestly", %{conn: conn, code: code} do
      stub_tablebase([{500, "boom"}])

      {:ok, view, _html} = live(conn, "/rooms/#{code}")

      render_click(view, "open-setup", %{})
      render_click(view, "setup-clear-board", %{})
      render_click(view, "setup-palette-drop", %{"piece" => "white_king", "square" => "4"})
      render_click(view, "setup-palette-drop", %{"piece" => "white_queen", "square" => "3"})
      render_click(view, "setup-palette-drop", %{"piece" => "black_king", "square" => "60"})
      render_click(view, "create-from-setup", %{})
      render_async(view, 1_000)

      assert has_element?(view, "#endgame-error")
    end
  end

  describe "comment dialog" do
    test "comments are saved and removed through the dialog", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "create-analysis", %{})
      render_click(view, "board-move", %{"from" => 12, "to" => 28})

      # No comment yet: the dialog opens with an empty field and no delete.
      render_click(view, "open-comment-editor", %{})
      assert has_element?(view, "#analysis-comment")
      refute has_element?(view, "#comment-clear")

      render_submit(view, "save-comment", %{"comment" => "A quiet start"})

      # The dialog closes and the comment is stored on the played move.
      refute has_element?(view, "#analysis-comment")

      analysis_id = room_analysis_id!(code)
      assert {:ok, analysis, _revision} = Analyses.get(analysis_id)
      assert hd(analysis.root.children).comment == "A quiet start"

      # Reopening offers deletion; deleting clears the comment.
      render_click(view, "open-comment-editor", %{})
      assert has_element?(view, "#comment-clear")
      render_click(view, "clear-comment", %{})
      refute has_element?(view, "#analysis-comment")

      assert {:ok, analysis, _revision} = Analyses.get(analysis_id)
      assert hd(analysis.root.children).comment in [nil, ""]
    end
  end

  describe "feature readout" do
    test "every catalogue feature has a curated description" do
      catalog = Jason.decode!(File.read!("priv/i18n/en.json"))

      missing =
        Features.Catalogue.all()
        |> Enum.map(& &1.id)
        |> Enum.reject(&Map.has_key?(catalog, "features." <> &1))

      assert missing == []
    end

    test "the features tab shows the catalogue readout and stores the vector", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, "/rooms/#{code}")
      render_click(view, "create-analysis", %{})

      render_click(view, "select-engine-tab", %{"tab" => "features"})

      assert has_element?(view, "#features-readout")
      refute has_element?(view, "#features-error")

      # Catalogue values for the starting position, labelled in words.
      assert has_element?(view, "#features-readout h4", "State")

      assert has_element?(
               view,
               "#features-readout button[data-feature='state.side_to_move']",
               "Side to move"
             )

      assert has_element?(
               view,
               "#features-readout button[data-feature='state.castling_rights']",
               "Castling rights"
             )

      # Values render (the starting position is white to move).
      assert has_element?(view, "#features-readout", "white")

      # Per-side values render per side, not as a key count: queens are 1-1
      # at the start, and false/false booleans read as an em dash.
      assert has_element?(
               view,
               "#features-readout button[data-feature='material.count.queen']",
               "W 1 · B 1"
             )

      assert has_element?(
               view,
               "#features-readout button[data-feature='pawns.rook_behind_passed']",
               "—"
             )

      # Rows with nothing in this position are dimmed.
      assert has_element?(view, "#features-readout button.opacity-60")

      # Dutch-worded ids get an English label; the tooltip carries the same
      # explanation as the detail strip.
      assert has_element?(
               view,
               "#features-readout button[data-feature='threats.aantal_checks']",
               "Checks available"
             )

      assert has_element?(
               view,
               "#features-readout button[data-feature='state.side_to_move'][title='Which colour is to move']"
             )

      # Clicking a row opens the detail strip: the curated description plus
      # the raw id and value; clicking again closes it.
      render_click(view, "feature-detail", %{"id" => "tension.pawn_tension"})

      assert has_element?(
               view,
               "#features-detail",
               "Squares attacked by pawns of both colours"
             )

      assert has_element?(view, "#features-detail", "tension.pawn_tension")

      render_click(view, "feature-detail", %{"id" => "tension.pawn_tension"})
      refute has_element?(view, "#features-detail")

      # A row with squares pins them on the board in the same click; the
      # overlay row shows the pinned feature; clicking again unpins.
      render_click(view, "feature-detail", %{"id" => "state.king_squares"})

      assert has_element?(view, "#chess-board span[data-highlight='white']")

      assert has_element?(
               view,
               "#features-readout button[data-feature='state.king_squares'][data-pinned='true']"
             )

      render_click(view, "feature-detail", %{"id" => "state.king_squares"})
      refute has_element?(view, "#chess-board span[data-highlight='white']")

      # The vector is stored for the position, ready for later search.
      [[position_id]] =
        Repo.query!("SELECT id FROM positions WHERE record = $1", [
          PositionCodec.encode(Position.starting_position())
        ]).rows

      assert Repo.query!(
               "SELECT count(*) FROM position_feature_vectors WHERE position_id = $1",
               [position_id]
             ).rows == [[1]]
    end
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

    # Settings stay editable while the engine runs; the hook restarts the
    # search when depth or lines change.
    render_click(view, "open-engine-settings", %{})

    html =
      render_change(view, "update-engine-settings", %{
        "depth" => "30",
        "multipv" => "4"
      })

    assert html =~ ~r/name="depth"[^>]*value="30"/
    assert html =~ ~r/name="multipv"[^>]*value="4"/
    assert html =~ "data-depth=\"30\""
    assert html =~ "data-multipv=\"4\""
    refute html =~ ~r/name="depth"[^>]*disabled/
    refute html =~ ~r/name="multipv"[^>]*disabled/
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

  test "pinning open files draws file bands on the board", %{conn: conn, code: code} do
    position =
      Position.starting_position()
      |> Position.remove_piece(8)
      |> Position.remove_piece(48)

    {:ok, analysis, _revision} = Analyses.create("open-file", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=open-file")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "lines.open_files"})

    assert has_element?(view, "#chess-board span[data-highlight='file']")

    assert has_element?(
             view,
             "#features-readout button[data-feature='lines.open_files'][data-pinned='true']"
           )

    # Unpinning clears the bands again.
    html = render_click(view, "feature-detail", %{"id" => "lines.open_files"})
    refute html =~ "data-highlight=\"file\""
  end

  test "pinning attacks and defended squares marks both sides", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("layers")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=layers")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "attacks.map"})

    assert has_element?(view, "#chess-board span[data-highlight='white']")
    assert has_element?(view, "#chess-board span[data-highlight='black']")

    render_click(view, "feature-detail", %{"id" => "attacks.defended_squares"})

    # Both pinned rows carry the accent state; unpinning clears the tints.
    assert has_element?(
             view,
             "#features-readout button[data-feature='attacks.map'][data-pinned='true']"
           )

    assert has_element?(
             view,
             "#features-readout button[data-feature='attacks.defended_squares'][data-pinned='true']"
           )

    html = render_click(view, "feature-detail", %{"id" => "attacks.map"})
    html = render_click(view, "feature-detail", %{"id" => "attacks.defended_squares"})
    refute html =~ "data-highlight="
  end

  test "pinning outposts marks the catalogue's outpost squares", %{conn: conn, code: code} do
    position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})

    {:ok, analysis, _revision} = Analyses.create("outpost", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=outpost")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "squares.outpost"})

    # The d4 pawn guards c5 and e5: both are white outposts in the catalogue.
    assert has_element?(view, "#chess-board-square-c5 span[data-highlight='white']")
    assert has_element?(view, "#chess-board-square-e5 span[data-highlight='white']")
  end

  test "pinning the rook count highlights the rooks from the position", %{
    conn: conn,
    code: code
  } do
    {:ok, analysis, _revision} = Analyses.create("rooks")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=rooks")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "material.count.rook"})

    # The start position has two rooks per side, drawn in the side's colour.
    assert has_element?(view, "#chess-board-square-a1 span[data-highlight='white']")
    assert has_element?(view, "#chess-board-square-h1 span[data-highlight='white']")
    assert has_element?(view, "#chess-board-square-a8 span[data-highlight='black']")
    assert has_element?(view, "#chess-board-square-h8 span[data-highlight='black']")
    refute has_element?(view, "#chess-board-square-b1 span[data-highlight='white']")

    assert has_element?(
             view,
             "#features-readout button[data-feature='material.count.rook'][data-pinned='true']"
           )

    html = render_click(view, "feature-detail", %{"id" => "material.count.rook"})
    refute html =~ "data-highlight="
  end

  test "pinning the bishop pair highlights only the side that has it", %{conn: conn, code: code} do
    position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("c1"), {:white, :bishop})
      |> Position.put_piece(Square.from_algebraic("f1"), {:white, :bishop})
      |> Position.put_piece(Square.from_algebraic("c8"), {:black, :bishop})

    {:ok, analysis, _revision} = Analyses.create("bishop-pair", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=bishop-pair")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "material.bishop_pair"})

    assert has_element?(view, "#chess-board-square-c1 span[data-highlight='white']")
    assert has_element?(view, "#chess-board-square-f1 span[data-highlight='white']")
    refute has_element?(view, "#chess-board-square-c8 span[data-highlight='black']")
  end

  test "pinning pawn chains highlights every square of the chain", %{conn: conn, code: code} do
    position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})
      |> Position.put_piece(Square.from_algebraic("e3"), {:white, :pawn})

    {:ok, analysis, _revision} = Analyses.create("chains", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=chains")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "pawns.chains"})

    # The catalogue stores chains as a list of chains; the engine flattens them.
    assert has_element?(view, "#chess-board-square-d4 span[data-highlight='white']")
    assert has_element?(view, "#chess-board-square-e3 span[data-highlight='white']")
  end

  test "the readout cues the rows that can draw on the board", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("drawable")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=drawable")

    render_click(view, "select-engine-tab", %{"tab" => "features"})

    # Counts (via the board hint) and square lists can draw; bare numbers cannot.
    assert has_element?(
             view,
             "#features-readout button[data-feature='material.count.rook'][data-drawable='true']"
           )

    assert has_element?(
             view,
             "#features-readout button[data-feature='attacks.attacked_squares'][data-drawable='true']"
           )

    assert has_element?(
             view,
             "#features-readout button[data-feature='material.total_value'][data-drawable='false']"
           )
  end

  test "pinning mobility per piece draws a heat map in three intensities", %{
    conn: conn,
    code: code
  } do
    position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("d4"), {:white, :queen})
      |> Position.put_piece(Square.from_algebraic("a2"), {:white, :pawn})

    {:ok, analysis, _revision} = Analyses.create("heat", position: position)
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=heat")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "mobility.per_piece"})

    # The queen is by far the most mobile piece: top intensity on d4; the
    # pawn's few moves sit in the lowest band; both sides carry a tint.
    assert has_element?(
             view,
             "#chess-board-square-d4 span[data-highlight='white'][data-heat-level='3']"
           )

    assert has_element?(
             view,
             "#chess-board-square-a2 span[data-highlight='white'][data-heat-level='1']"
           )

    assert has_element?(view, "#chess-board span[data-highlight='black'][data-heat-level]")

    # Heat rows count as drawable.
    assert has_element?(
             view,
             "#features-readout button[data-feature='mobility.per_piece'][data-drawable='true']"
           )

    html = render_click(view, "feature-detail", %{"id" => "mobility.per_piece"})
    refute html =~ "data-heat-level"
  end

  test "the starting position has no outposts to pin", %{conn: conn, code: code} do
    {:ok, analysis, _revision} = Analyses.create("outpost-start")
    :ok = Rooms.add_analysis(code, analysis.id)
    {:ok, view, _html} = live(conn, "/rooms/#{code}?a=outpost-start")

    render_click(view, "select-engine-tab", %{"tab" => "features"})
    render_click(view, "feature-detail", %{"id" => "squares.outpost"})

    # Nothing to draw: the row stays unpinned and the board stays clean.
    refute has_element?(view, "#chess-board span[data-highlight='white']")

    assert has_element?(
             view,
             "#features-readout button[data-feature='squares.outpost'][data-pinned='false']"
           )
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
    # Keys are semantic <kbd> elements in non-wrapping cells.
    assert html =~ ~r/<kbd[^>]*>Shift<\/kbd> \+ <kbd[^>]*>←<\/kbd> \/ <kbd[^>]*>→<\/kbd>/
    assert html =~ ~r/<kbd[^>]*>Home<\/kbd> \/ <kbd[^>]*>End<\/kbd>/
    assert html =~ "whitespace-nowrap"
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

  defp corpus_move(from, to),
    do: Move.new(Square.from_algebraic(from), Square.from_algebraic(to))

  # A tiny real corpus: Carlsen wins with 1.e4 e5, loses with 1.d4 d5, and
  # somebody else wins with 1.e4 c5. Cleanup deletes only the records; the
  # canonical games and positions stay shared and suite-truncated.
  defp seed_search_corpus do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    start_id = PositionStore.append(Position.starting_position())

    {:ok, win} =
      GameRecords.create(
        "search-win-#{suffix}",
        GameContent.new(start_id, [corpus_move("e2", "e4"), corpus_move("e7", "e5")]),
        GameStart.standard(),
        %{
          "white" => "Magnus Carlsen",
          "black" => "Opponent",
          "result" => "1-0",
          "white_elo" => "2830",
          "black_elo" => "2501",
          "date" => "2026.09.01"
        }
      )

    {:ok, loss} =
      GameRecords.create(
        "search-loss-#{suffix}",
        GameContent.new(start_id, [corpus_move("d2", "d4"), corpus_move("d7", "d5")]),
        GameStart.standard(),
        %{
          "white" => "Magnus Carlsen",
          "black" => "Opponent",
          "result" => "0-1",
          "white_elo" => "2830",
          "black_elo" => "2502",
          "date" => "2026.09.05"
        }
      )

    {:ok, other} =
      GameRecords.create(
        "search-other-#{suffix}",
        GameContent.new(start_id, [corpus_move("e2", "e4"), corpus_move("c7", "c5")]),
        GameStart.standard(),
        %{
          "white" => "Somebody Else",
          "black" => "Opponent",
          "result" => "1-0",
          "white_elo" => "2505",
          "black_elo" => "2515",
          "date" => "2026.09.01"
        }
      )

    # Same pawn structure as after 1.e4 e5, but a different exact position
    # (the knight is already on f3): 1.Nf3 e5 2.e4.
    {:ok, transpo} =
      GameRecords.create(
        "search-transpo-#{suffix}",
        GameContent.new(
          start_id,
          [corpus_move("g1", "f3"), corpus_move("e7", "e5"), corpus_move("e2", "e4")]
        ),
        GameStart.standard(),
        %{
          "white" => "Transpo Player",
          "black" => "Opponent",
          "result" => "1/2-1/2",
          "white_elo" => "2510",
          "black_elo" => "2499",
          "date" => "2026.09.03"
        }
      )

    %{
      carlsen_win: win.id,
      carlsen_loss: loss.id,
      other_win: other.id,
      transpo: transpo.id,
      record_ids: [win.id, loss.id, other.id, transpo.id]
    }
  end

  defp cleanup_search_corpus(corpus) do
    Repo.query!("DELETE FROM game_records WHERE record_id = ANY($1)", [corpus.record_ids])
  end

  defp room_analysis_id!(code) do
    {:ok, room} =
      Rooms.get(code)

    [analysis_id] =
      Analysis.Room.analysis_ids(room)

    analysis_id
  end

  defp room_analysis_ids(code) do
    {:ok, room} = Rooms.get(code)
    Analysis.Room.analysis_ids(room)
  end

  # A queued-response stub for the provider HTTP seam (see Web.GameImport).
  defp stub_game_import(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    request = fn _method, _payload, _http, _options ->
      Agent.get_and_update(agent, fn
        [{status, body} | rest] -> {{:ok, {{~c"HTTP/1.1", status, ~c""}, [], body}}, rest}
      end)
    end

    Application.put_env(:web, :game_import_request, request)
  end

  defp stub_tablebase(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    request = fn :get, _payload, _http, _options ->
      Agent.get_and_update(agent, fn
        [{status, body} | rest] -> {{:ok, {{~c"HTTP/1.1", status, ~c""}, [], body}}, rest}
      end)
    end

    Application.put_env(:web, :tablebase_request, request)
    agent
  end
end
