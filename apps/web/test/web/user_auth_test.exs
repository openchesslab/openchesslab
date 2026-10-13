defmodule Web.UserAuthTest do
  use Web.ConnCase, async: false

  alias Analysis.Rooms
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  defmodule ProbeLive do
    use Phoenix.LiveView
    on_mount {Web.UserAuth, :default}

    def mount(_params, _session, socket), do: {:ok, Phoenix.Component.assign(socket, :seen, "")}

    def render(assigns) do
      ~H"""
      <p id="identity">{if @current_user, do: @current_user.id, else: "guest"}</p>
      <p id="seen">{@seen}</p>
      <button phx-click="probe">Probe</button>
      """
    end

    def handle_event("probe", _params, socket) do
      identity = if socket.assigns.current_user, do: socket.assigns.current_user.id, else: "guest"
      {:noreply, Phoenix.Component.assign(socket, :seen, identity)}
    end
  end

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    {:ok, other_session} = UserSessions.create(other.id)

    on_exit(fn ->
      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{user: user, other: other, session: session, other_session: other_session}
  end

  test "HTTP requests resolve only the protected session credential", context do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        user_token: context.session.token,
        user_id: context.other.id
      })
      |> get("/?user_id=#{context.other.id}&user_token=#{context.other_session.token}")

    assert conn.assigns.current_user == context.user
    assert response(conn, 200)
  end

  test "anonymous, malformed and asserted identity sessions stay guests", context do
    for token <- [nil, "invalid", context.user.id] do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{user_token: token, user_id: context.user.id})
        |> get("/")

      assert conn.assigns.current_user == nil
      assert response(conn, 200)
    end
  end

  test "revoked credentials in a retained encrypted cookie do not authenticate", context do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: context.session.token})
      |> get("/")

    assert conn.assigns.current_user == context.user
    UserSessions.revoke(context.session.token)
    replay = get(recycle(conn), "/")
    assert get_session(replay, :user_token) == context.session.token
    assert replay.assigns.current_user == nil
  end

  test "deleted users and expired sessions fail closed on requests and mounts", context do
    expire(context.session.token)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: context.session.token})
      |> get("/")

    assert conn.assigns.current_user == nil

    {:ok, view, _html} =
      live_isolated(build_conn(), ProbeLive, session: %{"user_token" => context.session.token})

    assert has_element?(view, "#identity", "guest")

    Users.delete(context.other.id)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: context.other_session.token})
      |> get("/")

    assert conn.assigns.current_user == nil
  end

  test "connected mount resolves the credential and event parameters cannot change identity",
       context do
    {:ok, view, _html} =
      live_isolated(build_conn(), ProbeLive,
        session: %{"user_token" => context.session.token, "user_id" => context.other.id}
      )

    assert has_element?(view, "#identity", context.user.id)

    render_click(view, "probe", %{
      "user_id" => context.other.id,
      "user_token" => context.other_session.token
    })

    assert has_element?(view, "#seen", context.user.id)
    refute render(view) =~ context.session.token
  end

  test "connected mount rechecks a credential revoked after the initial HTTP render", context do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: context.session.token})
      |> get("/")

    assert conn.assigns.current_user == context.user
    UserSessions.revoke(context.session.token)
    {:ok, view, _html} = live(conn)
    assert :sys.get_state(view.pid).socket.assigns.current_user == nil
  end

  test "each event rechecks revocation before its handler runs", context do
    {:ok, view, _html} =
      live_isolated(build_conn(), ProbeLive, session: %{"user_token" => context.session.token})

    assert has_element?(view, "#identity", context.user.id)
    UserSessions.revoke(context.session.token)
    render_click(view, "probe", %{})
    assert has_element?(view, "#identity", "guest")
    assert has_element?(view, "#seen", "guest")
  end

  test "each event rechecks expiry before its handler runs", context do
    {:ok, view, _html} =
      live_isolated(build_conn(), ProbeLive, session: %{"user_token" => context.session.token})

    expire(context.session.token)
    render_click(view, "probe", %{})
    assert has_element?(view, "#identity", "guest")
    assert has_element?(view, "#seen", "guest")
  end

  test "real public routes apply the mount hook while rooms remain guest-accessible", context do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: context.session.token})
      |> get("/")

    {:ok, home, _html} = live(conn)
    assert :sys.get_state(home.pid).socket.assigns.current_user == context.user

    code = "AUTH" <> Base.encode16(:crypto.strong_rand_bytes(4))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)
    {:ok, room, _html} = live(build_conn(), "/rooms/#{code}")
    assert :sys.get_state(room.pid).socket.assigns.current_user == nil
    assert render(room) =~ "No analyses in this room yet"
  end

  defp expire(token) do
    Repo.query!(
      "UPDATE user_sessions SET created_at = timezone('UTC', statement_timestamp()) - interval '2 days', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second' WHERE token_hash = $1",
      [:crypto.hash(:sha256, token)],
      log: false
    )
  end
end
