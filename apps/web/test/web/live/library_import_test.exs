defmodule Web.LibraryImportTest do
  use Web.ConnCase, async: false

  alias Analysis.{Analyses, AnalysisStore, GameContent, GameRecords, GameStart, Rooms}
  alias Analysis.UserLibrary
  alias Analysis.UserSessions
  alias Analysis.Users
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  defp move(from, to), do: Move.new(Square.from_algebraic(from), Square.from_algebraic(to))

  setup do
    before_ids = ids()
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    code = "LIM" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    record_id = "import-record-#{suffix}"
    game_entry_id = "import-game-#{suffix}"
    plain_id = "import-plain-#{suffix}"

    initial_position_id = Analysis.PositionStore.append(Position.starting_position())
    content = GameContent.new(initial_position_id, [move("e2", "e4"), move("e7", "e5")])

    {:ok, _record} =
      GameRecords.create(record_id, content, GameStart.standard(), %{
        "white" => "W",
        "black" => "B"
      })

    {:ok, _analysis, 1} = Analyses.create_from_game_record(game_entry_id, record_id)
    {:ok, _plain, 1} = Analyses.create(plain_id)
    assert {:ok, _analysis, 2} = Analyses.set_comment(game_entry_id, [0], "Private teacher notes")
    :ok = UserLibrary.save(user.id, game_entry_id)
    :ok = UserLibrary.save(user.id, plain_id)

    on_exit(fn ->
      Rooms.stop_room(code)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = ANY($1)", [[game_entry_id, plain_id]])
      Enum.each(ids() -- before_ids, &Users.delete/1)
    end)

    %{
      user: user,
      session: session,
      code: code,
      record_id: record_id,
      game_entry_id: game_entry_id,
      plain_id: plain_id
    }
  end

  defp open_library_tab(view) do
    render_click(view, "open-import", %{})
    render_click(view, "set-import-source", %{"source" => "library"})
  end

  test "the My Library tab lists real entries with the three branch actions", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    html = open_library_tab(view)

    refute html =~ "local demo fixtures"
    assert has_element?(view, "#library-entries li", ctx.game_entry_id)
    assert has_element?(view, "#saved-#{ctx.game_entry_id} button[phx-click='library-add-game']")
    assert has_element?(view, "#saved-#{ctx.game_entry_id} button[phx-click='library-add-copy']")
    assert has_element?(view, "#saved-#{ctx.game_entry_id} button[phx-click='library-share']")

    assert has_element?(
             view,
             "#saved-#{ctx.game_entry_id} a[href='/library/#{ctx.game_entry_id}']"
           )

    # Entries without an underlying game do not offer the game branch.
    assert has_element?(view, "#saved-#{ctx.plain_id} button[phx-click='library-add-copy']")
    refute has_element?(view, "#saved-#{ctx.plain_id} button[phx-click='library-add-game']")
  end

  test "guests see the login hint instead of entries", ctx do
    {:ok, view, _} = live(build_conn(), "/rooms/#{ctx.code}")
    html = open_library_tab(view)

    assert html =~ Web.I18n.t("auth.loginRequired", "en")
    refute has_element?(view, "#library-entries")
    refute html =~ ctx.game_entry_id
  end

  test "branching only the game adds a fresh analysis without the private work", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    html =
      render_click(view, "library-add-game", %{
        "id" => ctx.game_entry_id,
        "user_id" => Ecto.UUID.generate()
      })

    assert html =~ "Added to this room."

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    [new_id] = room.analysis_ids -- [ctx.game_entry_id]
    refute new_id == ctx.game_entry_id

    assert {:ok, fresh, 1} = AnalysisStore.get(new_id)
    assert fresh.source_game_record_id == ctx.record_id
    assert Analysis.Node.comment(Analysis.Analysis.node_at(fresh, [0])) == nil

    # The entry keeps its private work.
    assert {:ok, entry, 2} = AnalysisStore.get(ctx.game_entry_id)
    assert Analysis.Node.comment(Analysis.Analysis.node_at(entry, [0])) == "Private teacher notes"
  end

  test "branching a copy keeps later room work out of the library entry", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    html =
      render_click(view, "library-add-copy", %{"id" => ctx.game_entry_id, "user_id" => "forged"})

    assert html =~ "Added to this room."

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    [new_id] = room.analysis_ids -- [ctx.game_entry_id]
    assert {:ok, copy, 1} = AnalysisStore.get(new_id)
    assert {:ok, entry, 2} = AnalysisStore.get(ctx.game_entry_id)
    assert %{copy | id: entry.id} == entry

    # Room work on the fresh copy never flows back into the entry.
    assert {:ok, _, 2} = Analyses.set_comment(new_id, [0], "Room work")
    assert {:ok, ^entry, 2} = AnalysisStore.get(ctx.game_entry_id)
  end

  test "live sharing adds the exact analysis and fills the star", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    html =
      render_click(view, "library-share", %{"id" => ctx.game_entry_id, "user_id" => "forged"})

    assert html =~ "Shared live"

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    assert room.analysis_ids == [ctx.game_entry_id]
    assert has_element?(view, "#track-#{ctx.game_entry_id}[aria-pressed='true']")
  end

  test "guests and revoked sessions cannot branch, even with forged parameters", ctx do
    {:ok, guest, _} = live(build_conn(), "/rooms/#{ctx.code}")
    open_library_tab(guest)

    for event <- ["library-add-game", "library-add-copy", "library-share"] do
      render_click(guest, event, %{"id" => ctx.game_entry_id, "user_id" => ctx.user.id})
    end

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    assert room.analysis_ids == []

    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)
    UserSessions.revoke(ctx.session.token)

    for event <- ["library-add-game", "library-add-copy", "library-share"] do
      render_click(view, event, %{"id" => ctx.game_entry_id, "user_id" => ctx.user.id})
    end

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    assert room.analysis_ids == []
  end

  test "missing entries fail the branch actions without changing the room", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    html = render_click(view, "library-add-copy", %{"id" => "missing", "user_id" => ctx.user.id})
    assert html =~ "Could not add this analysis to the room."

    assert {:ok, room} = Analysis.RoomStore.get(ctx.code)
    assert room.analysis_ids == []
  end

  test "rename and removal still work inside the tab", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    render_click(view, "library-start-rename", %{"id" => ctx.plain_id})

    render_submit(view, "library-rename", %{
      "title" => "My open Sicilian",
      "id" => ctx.game_entry_id
    })

    assert {:ok, "My open Sicilian"} = UserLibrary.title(ctx.user.id, ctx.plain_id)
    assert {:ok, nil} = UserLibrary.title(ctx.user.id, ctx.game_entry_id)

    render_click(view, "library-remove", %{"id" => ctx.plain_id})
    assert Enum.sort(UserLibrary.list(ctx.user.id)) == Enum.sort([ctx.game_entry_id])
  end

  test "the removed /library and /account routes are gone", ctx do
    for path <- ["/library", "/account"] do
      assert response(get(authenticated(ctx), path), 404)
    end
  end

  test "paging ignores submitted user and cursor values and keeps at most 50 entries", ctx do
    ids =
      for n <- 1..51,
          do:
            "tab-page-#{String.pad_leading(to_string(n), 3, "0")}-#{Base.encode16(:crypto.strong_rand_bytes(2))}"

    on_exit(fn ->
      Repo.query!("DELETE FROM analyses WHERE analysis_id = ANY($1)", [ids])
    end)

    for id <- ids do
      {:ok, 1} = AnalysisStore.insert(Analysis.Analysis.new(id, 42))
      :ok = UserLibrary.save(ctx.user.id, id)
    end

    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}")
    open_library_tab(view)

    assert length(:sys.get_state(view.pid).socket.assigns.library_entries) == 50
    assert has_element?(view, "button[phx-click='library-next-page']")

    render_click(view, "library-next-page", %{"user_id" => ctx.user.id, "cursor" => "forged"})

    assert length(:sys.get_state(view.pid).socket.assigns.library_entries) == 3
    assert has_element?(view, "#library-entries li", List.last(ids))

    render_click(view, "library-first-page", %{})
    assert has_element?(view, "#library-entries li", List.first(ids))
  end

  test "the account menu no longer opens a library surface", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    refute has_element?(view, "#personal-library-button")
    refute has_element?(view, "#library-modal-title")
    assert has_element?(view, "#linked-accounts-button")
  end

  defp authenticated(ctx),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})

  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
