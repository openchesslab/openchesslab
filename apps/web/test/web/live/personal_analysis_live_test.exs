defmodule Web.PersonalAnalysisLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analyses
  alias Analysis.AnalysisStore
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    {:ok, other_session} = UserSessions.create(other.id)
    source = "editor-source-" <> Ecto.UUID.generate()
    room = "editor-room-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(source)
    :ok = RoomStore.create(room)
    :ok = RoomStore.add_analysis(room, source)
    {:ok, id} = UserLibrary.copy_from_room(user.id, room, source)

    on_exit(fn ->
      RoomStore.delete(room)

      for analysis_id <- [source, id],
          do: Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [analysis_id])

      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{
      user: user,
      other: other,
      session: session,
      other_session: other_session,
      source: source,
      room: room,
      id: id
    }
  end

  test "library opens a private editor and restores persisted edits without a room", ctx do
    {:ok, library, _} = live(conn(ctx.session), "/library")
    assert has_element?(library, "a[href='/library/#{ctx.id}']")
    {:ok, view, html} = live(conn(ctx.session), "/library/#{ctx.id}")
    assert html =~ "Personal analysis"
    assert has_element?(view, "#chess-board")
    render_click(view, "board-square", %{"square" => "12"})
    assert :sys.get_state(view.pid).socket.assigns.legal_targets != []
    render_click(view, "board-square", %{"square" => "28"})
    assert_patch(view, "/library/#{ctx.id}?p=0")

    render_submit(view, "save-comment", %{
      "comment" => "Only mine",
      "id" => ctx.source,
      "user_id" => ctx.other.id
    })

    render_click(view, "toggle-nag", %{"nag" => "1"})
    {:ok, reopened, _} = live(conn(ctx.session), "/library/#{ctx.id}?p=0")
    assert has_element?(reopened, "#personal-comment-text", "Only mine")
    assert {:ok, copy, 4} = AnalysisStore.get(ctx.id)
    assert Analysis.Node.nags(Analysis.Analysis.node_at(copy, [0])) == [1]
    assert {:ok, source, 1} = AnalysisStore.get(ctx.source)
    assert source.root.children == []
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert room.analysis_ids == [ctx.source]
  end

  test "guests and forged credentials cannot request private content", ctx do
    for token <- [nil, "invalid", ctx.user.id] do
      response =
        build_conn()
        |> Plug.Test.init_test_session(%{user_token: token})
        |> get("/library/#{ctx.id}?user_id=#{ctx.user.id}")

      assert redirected_to(response) == "/"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end
  end

  test "another user's ID, a missing analysis and a room source have the same denial", ctx do
    for {session, id} <- [
          {ctx.other_session, ctx.id},
          {ctx.session, "missing"},
          {ctx.session, ctx.source}
        ] do
      assert {:error, {:redirect, %{to: "/library"}}} =
               live(conn(session), "/library/#{id}?user_id=#{ctx.user.id}")
    end
  end

  test "membership removal denies events and patches before accessing cached content", ctx do
    {:ok, event_view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    {:ok, patch_view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    UserLibrary.remove(ctx.user.id, ctx.id)

    assert {:error, {:redirect, %{to: "/library"}}} =
             render_submit(event_view, "save-comment", %{"comment" => "Denied"})

    assert {:error, {:redirect, %{to: "/library"}}} =
             render_patch(patch_view, "/library/#{ctx.id}?p=0")

    assert {:ok, _, 1} = AnalysisStore.get(ctx.id)
  end

  test "revocation between HTTP and connected mount denies the editor", ctx do
    response = get(conn(ctx.session), "/library/#{ctx.id}")
    assert html_response(response, 200) =~ "Personal analysis"
    UserSessions.revoke(ctx.session.token)
    assert {:error, {:redirect, %{to: "/"}}} = live(response)
  end

  test "revocation blocks writes and expiry blocks navigation", ctx do
    {:ok, view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    UserSessions.revoke(ctx.session.token)

    assert {:error, {:redirect, %{to: "/"}}} =
             render_submit(view, "save-comment", %{"comment" => "Denied"})

    assert {:ok, _, 1} = AnalysisStore.get(ctx.id)
    {:ok, fresh} = UserSessions.create(ctx.user.id)
    {:ok, view, _} = live(conn(fresh), "/library/#{ctx.id}")

    Repo.query!(
      "UPDATE user_sessions SET created_at = timezone('UTC', statement_timestamp()) - interval '2 days', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second' WHERE token_hash = $1",
      [:crypto.hash(:sha256, fresh.token)],
      log: false
    )

    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/library/#{ctx.id}?p=0")
  end

  test "stale-tab writes report a conflict and load the latest version", ctx do
    {:ok, view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    {:ok, _, 2} = UserLibrary.edit_private(ctx.user.id, ctx.id, 1, [], {:comment, "Other tab"})
    html = render_submit(view, "save-comment", %{"comment" => "Stale"})
    assert html =~ "changed in another tab"
    assert has_element?(view, "#personal-comment-text", "Other tab")
    assert {:ok, analysis, 2} = AnalysisStore.get(ctx.id)
    assert analysis.root.comment == "Other tab"
  end

  test "invalid paths fall back to the root and Dutch labels render", ctx do
    {:ok, view, html} =
      live(
        put_req_cookie(conn(ctx.session), "_ocl_locale", "nl"),
        "/library/#{ctx.id}?p=-1,garbage"
      )

    assert html =~ "Persoonlijke analyse"
    assert :sys.get_state(view.pid).socket.assigns.current_path == []
    render_click(view, "board-move", %{"from" => "invalid", "to" => "90"})
    assert {:ok, _, 1} = AnalysisStore.get(ctx.id)
  end

  test "variations can be promoted and removed through the editor", ctx do
    {:ok, view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    render_click(view, "board-move", %{"from" => 12, "to" => 28})
    render_click(view, "first-move", %{})
    render_click(view, "board-move", %{"from" => 11, "to" => 27})
    assert_patch(view, "/library/#{ctx.id}?p=1")
    render_click(view, "promote-variation", %{})
    assert_patch(view, "/library/#{ctx.id}?p=0")
    render_click(view, "move-tree-key", %{"path" => "0", "key" => "ArrowDown"})
    assert_patch(view, "/library/#{ctx.id}?p=1")
    render_click(view, "remove-subtree", %{})
    assert_patch(view, "/library/#{ctx.id}")
    assert {:ok, analysis, 5} = AnalysisStore.get(ctx.id)
    assert length(analysis.root.children) == 1
    assert hd(analysis.root.children).transition == {:move, Chess.Move.new(11, 27)}
  end

  test "pawn promotion waits for an explicit piece choice", ctx do
    position =
      Chess.Position.new()
      |> Chess.Position.put_piece(52, {:white, :pawn})
      |> Chess.Position.put_piece(4, {:white, :king})
      |> Chess.Position.put_piece(56, {:black, :king})

    position_id = Analysis.PositionStore.append(position)
    {:ok, old, 1} = AnalysisStore.get(ctx.id)
    {:ok, 2} = AnalysisStore.update(%{old | root: Analysis.Node.new(position_id)}, 1)
    {:ok, view, _} = live(conn(ctx.session), "/library/#{ctx.id}")
    render_click(view, "board-move", %{"from" => 52, "to" => 60})
    assert has_element?(view, "#personal-promotion")
    assert {:ok, _, 2} = AnalysisStore.get(ctx.id)
    render_click(view, "promote-pawn", %{"promotion" => "knight"})
    refute has_element?(view, "#personal-promotion")
    assert {:ok, analysis, 3} = AnalysisStore.get(ctx.id)
    node = Analysis.Analysis.node_at(analysis, [0])
    assert {:ok, promoted} = Analysis.PositionStore.get(node.position_id)
    assert Chess.Position.piece_at(promoted, 60) == {:white, :knight}
  end

  defp conn(session), do: Plug.Test.init_test_session(build_conn(), %{user_token: session.token})
end
