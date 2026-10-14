defmodule Web.LibraryLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    suffix = Base.encode16(:crypto.strong_rand_bytes(6))
    own = "own-#{suffix}"
    theirs = "theirs-#{suffix}"
    for id <- [own, theirs], do: AnalysisStore.insert(AnalysisModel.new(id, 42))
    :ok = UserLibrary.save(user.id, own)
    :ok = UserLibrary.save(other.id, own)
    :ok = UserLibrary.save(other.id, theirs)

    on_exit(fn ->
      Users.delete(user.id)
      Users.delete(other.id)
      for id <- [own, theirs], do: AnalysisStore.delete(id, 1)
    end)

    %{user: user, other: other, session: session, own: own, theirs: theirs}
  end

  test "anonymous and forged identity requests redirect before rendering private content", ctx do
    for token <- [nil, "invalid", ctx.user.id] do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{user_id: ctx.user.id, user_token: token})
        |> get("/library?user_id=#{ctx.user.id}")

      assert redirected_to(conn) == "/"
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      refute conn.resp_body =~ ctx.own
    end
  end

  test "library renders only the authenticated user's references, including in Dutch", ctx do
    conn =
      authenticated(ctx)
      |> put_req_cookie("_ocl_locale", "nl")
      |> put_req_cookie("_ocl_theme", "dark")
      |> get("/library?user_id=#{ctx.other.id}")

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert html_response(conn, 200) =~ ctx.own
    refute html_response(conn, 200) =~ ctx.theirs
    {:ok, view, html} = live(conn)
    assert html =~ "Mijn bibliotheek"
    assert has_element?(view, "#library-entries li", ctx.own)
    refute html =~ ctx.theirs
    refute html =~ ctx.user.id
    refute html =~ ctx.session.token
  end

  test "removal cannot select another user and leaves the shared analysis intact", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/library")
    render_click(view, "remove", %{"id" => ctx.theirs, "user_id" => ctx.other.id})
    assert ctx.theirs in UserLibrary.list(ctx.other.id)

    render_click(view, "remove", %{"id" => ctx.own, "user_id" => ctx.other.id})
    assert UserLibrary.list(ctx.user.id) == []
    assert ctx.own in UserLibrary.list(ctx.other.id)
    assert {:ok, _, 1} = AnalysisStore.get(ctx.own)
    assert has_element?(view, "#library-empty")
  end

  test "a revoked credential cannot connect after a valid HTTP render", ctx do
    conn = authenticated(ctx) |> get("/library")
    assert response(conn, 200)
    UserSessions.revoke(ctx.session.token)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn)
  end

  test "revocation halts removal before the event handler", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/library")
    UserSessions.revoke(ctx.session.token)
    assert {:error, {:redirect, %{to: "/"}}} = render_click(view, "remove", %{"id" => ctx.own})
    assert UserLibrary.list(ctx.user.id) == [ctx.own]
  end

  test "expiry halts live navigation before reading the library", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/library")
    expire(ctx.session.token)

    assert {:error, {:redirect, %{to: "/"}}} =
             render_patch(view, "/library?user_id=#{ctx.other.id}")
  end

  test "expired sessions and deleted users cannot request the page", ctx do
    expire(ctx.session.token)
    assert redirected_to(get(authenticated(ctx), "/library")) == "/"
    {:ok, new_session} = UserSessions.create(ctx.user.id)
    Users.delete(ctx.user.id)
    conn = build_conn() |> Plug.Test.init_test_session(%{user_token: new_session.token})
    assert redirected_to(get(conn, "/library")) == "/"
  end

  test "navigation is offered only to authenticated users", ctx do
    {:ok, guest, _} = live(build_conn(), "/")
    refute has_element?(guest, "#personal-library-link")
    {:ok, signed_in, _} = live(authenticated(ctx), "/")
    assert has_element?(signed_in, "#personal-library-link[href='/library']", "My library")
  end

  test "paging ignores submitted user and cursor values and keeps at most 50 entries", ctx do
    ids = for n <- 1..51, do: "page-#{ctx.own}-#{String.pad_leading(to_string(n), 3, "0")}"
    on_exit(fn -> for id <- ids, do: AnalysisStore.delete(id, 1) end)

    for id <- ids do
      {:ok, 1} = AnalysisStore.insert(AnalysisModel.new(id, 42))
      :ok = UserLibrary.save(ctx.user.id, id)
    end

    {:ok, view, _} = live(authenticated(ctx), "/library")
    assert length(:sys.get_state(view.pid).socket.assigns.entries) == 50
    assert has_element?(view, "button[phx-click='next-page']")
    render_click(view, "next-page", %{"user_id" => ctx.other.id, "cursor" => ctx.theirs})
    assert length(:sys.get_state(view.pid).socket.assigns.entries) == 2
    assert has_element?(view, "#library-entries li", List.last(ids))
    refute render(view) =~ ctx.theirs
    refute has_element?(view, "button[phx-click='next-page']")
    render_click(view, "first-page", %{})
    assert has_element?(view, "#library-entries li", ctx.own)
  end

  defp authenticated(ctx),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})

  defp expire(token) do
    Repo.query!(
      "UPDATE user_sessions SET created_at = timezone('UTC', statement_timestamp()) - interval '2 days', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second' WHERE token_hash = $1",
      [:crypto.hash(:sha256, token)],
      log: false
    )
  end
end
