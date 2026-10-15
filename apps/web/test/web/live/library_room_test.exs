defmodule Web.LibraryRoomTest do
  use Web.ConnCase, async: false
  alias Analysis.{Analyses, RoomStore, Rooms, UserLibrary, Users, UserSessions}
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    id = "open-room-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(id)
    :ok = UserLibrary.save(user.id, id)

    on_exit(fn ->
      for [code] <-
            Repo.query!("SELECT id FROM rooms WHERE owner_user_id = $1", [
              Ecto.UUID.dump!(user.id)
            ]).rows do
        Rooms.stop_room(code)
        RoomStore.delete(code)
      end

      Users.delete(user.id)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
    end)

    %{user: user, session: session, id: id}
  end

  test "library opens the ordinary room editor with tools and private access", ctx do
    conn = Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})
    {:ok, view, _} = live(conn, "/")
    render_click(view, "open-library")

    view
    |> element("button[phx-click='library-open'][phx-value-id='#{ctx.id}']")
    |> render_click()

    {url, _} = assert_redirect(view)
    assert url =~ "/rooms/"
    {:ok, editor, _} = live(conn, url)
    state = :sys.get_state(editor.pid).socket.assigns
    assert state.selected_analysis_id == ctx.id
    assert RoomStore.member?(state.room_code, ctx.user.id)
    assert has_element?(editor, "#chess-board")
    assert render(editor) =~ "Stockfish"
    render_hook(element(editor, "#chess-board"), "board-move", %{"from" => 12, "to" => 28})
    assert {:ok, _, 2} = Analyses.get(ctx.id)
    {:ok, reopened, _} = live(conn, url)
    assert render_click(reopened, "last-move", %{}) =~ "occupied by white pawn e4"
    {:ok, guest, html} = live(build_conn(), url)
    refute has_element?(guest, "#chess-board")
    refute html =~ ctx.id
  end

  test "guest, revoked credential and forged ownership cannot open an entry", ctx do
    for token <- [nil, ctx.session.token] do
      conn = Plug.Test.init_test_session(build_conn(), %{user_token: token})
      {:ok, view, _} = live(conn, "/")
      if token, do: UserSessions.revoke(token)
      render_click(view, "library-open", %{"id" => ctx.id, "user_id" => ctx.user.id})
      refute_redirected(view)
    end

    assert Repo.query!("SELECT id FROM rooms WHERE owner_user_id = $1", [
             Ecto.UUID.dump!(ctx.user.id)
           ]).rows == []
  end
end
