defmodule Web.SessionControllerTest do
  use Web.ConnCase, async: false

  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  @origin "https://openchesslab.example"

  setup do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    on_exit(fn -> Users.delete(user.id) end)
    %{user: user, session: session}
  end

  test "logout revokes the current token, clears browser cookies and resets CSRF", %{
    session: session
  } do
    {browser, csrf} = browser(session.token)
    browser = put_req_cookie(recycle(browser), "_ocl_lichess_attempt", "pending-browser-token")
    result = logout(browser, csrf)

    assert redirected_to(result) == "/"
    assert :not_found = UserSessions.user_for_token(session.token)
    assert result.resp_cookies["_web_key"].max_age == 0

    assert Enum.any?(
             get_resp_header(result, "set-cookie"),
             &String.starts_with?(&1, "_web_key=; path=/;")
           )

    assert result.resp_cookies["_ocl_lichess_attempt"].max_age == 0
    assert result.resp_cookies["_ocl_lichess_attempt"].path == "/auth/lichess"
    assert get_session(result) == %{}
    assert get_resp_header(result, "cache-control") == ["no-store"]
    assert get_resp_header(result, "referrer-policy") == ["no-referrer"]

    home = get(recycle(result), @origin <> "/")
    assert get_session(home, :user_token) == nil

    [_, next_csrf] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))

    refute next_csrf == csrf
  end

  test "another session for the same user survives logout", %{user: user, session: session} do
    {:ok, other_session} = UserSessions.create(user.id)
    {browser, csrf} = browser(session.token)
    logout(browser, csrf)
    assert :not_found = UserSessions.user_for_token(session.token)
    assert {:ok, ^user} = UserSessions.user_for_token(other_session.token)
  end

  test "logout closes every transport for this credential but leaves other sessions alone", %{
    user: user,
    session: session
  } do
    {:ok, other} = UserSessions.create(user.id)
    other_topic = Web.UserAuth.live_socket_id(other.token)
    Web.Endpoint.subscribe(other_topic)
    {browser, csrf} = browser(session.token)
    topic = get_session(browser, :live_socket_id)
    refute topic =~ session.token

    supervisor = start_supervised!(Task.Supervisor)
    owner = self()

    transports =
      for _tab <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          {:ok, state} =
            Phoenix.LiveView.Socket.connect(%{
              endpoint: Web.Endpoint,
              options: [serializer: [{Phoenix.Socket.V2.JSONSerializer, "~> 2.0.0"}]],
              transport: :websocket,
              params: %{"vsn" => "2.0.0"},
              connect_info: %{session: get_session(browser)}
            })

          {:ok, state} = Phoenix.LiveView.Socket.init(state)
          send(owner, {:transport_ready, self()})

          receive do
            %Phoenix.Socket.Broadcast{} = message ->
              Phoenix.LiveView.Socket.handle_info(message, state)
          end
        end)
      end

    for %{pid: pid} <- transports, do: assert_receive({:transport_ready, ^pid})
    logout(browser, csrf, %{"live_socket_id" => other_topic, "user_token" => other.token})

    for task <- transports do
      assert {:stop, {:shutdown, :disconnected}, 1001, _state} = Task.await(task)
    end

    refute_received %Phoenix.Socket.Broadcast{topic: ^other_topic, event: "disconnect"}
    assert {:ok, ^user} = UserSessions.user_for_token(other.token)

    {:ok, view, _html} = live(get(recycle(browser), @origin <> "/"))
    assert :sys.get_state(view.pid).socket.assigns.current_user == nil
  end

  test "request parameters cannot revoke another user or select a redirect", %{session: session} do
    {:ok, other_user} = Users.create()
    on_exit(fn -> Users.delete(other_user.id) end)
    {:ok, other_session} = UserSessions.create(other_user.id)
    {browser, csrf} = browser(session.token)

    result =
      logout(browser, csrf, %{
        "user_id" => other_user.id,
        "user_token" => other_session.token,
        "return_to" => "https://attacker.example"
      })

    assert redirected_to(result) == "/"
    assert :not_found = UserSessions.user_for_token(session.token)
    assert {:ok, ^other_user} = UserSessions.user_for_token(other_session.token)
  end

  test "missing, invalid and another browser's CSRF token cannot log out", %{
    session: session,
    user: user
  } do
    {first, first_csrf} = browser(session.token)
    {second, _second_csrf} = browser(session.token)

    for {conn, csrf} <- [{first, nil}, {first, "wrong-token"}, {second, first_csrf}] do
      assert_error_sent 403, fn -> logout(conn, csrf) end
      assert {:ok, ^user} = UserSessions.user_for_token(session.token)
    end
  end

  test "GET cannot log out", %{session: session, user: user} do
    {browser, _csrf} = browser(session.token)
    assert browser |> recycle() |> get(@origin <> "/auth/logout") |> response(404)
    assert {:ok, ^user} = UserSessions.user_for_token(session.token)
  end

  test "an old encrypted browser cookie cannot restore a revoked credential", %{session: session} do
    {browser, csrf} = browser(session.token)
    logout(browser, csrf)
    replay = get(recycle(browser), @origin <> "/")
    # A stateless cookie may still decrypt. Authorization must resolve its
    # credential against PostgreSQL rather than trusting its mere presence.
    assert get_session(replay, :user_token) == session.token
    assert :not_found = UserSessions.user_for_token(get_session(replay, :user_token))
  end

  test "anonymous and repeated logout are safe", %{session: session} do
    {browser, csrf} = browser(nil)
    first = logout(browser, csrf)
    assert redirected_to(first) == "/"
    next = get(recycle(first), @origin <> "/")

    [_, next_csrf] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(next, 200))

    second = logout(next, next_csrf)
    assert redirected_to(second) == "/"
    assert {:ok, _user} = UserSessions.user_for_token(session.token)
  end

  test "expired sessions are removed at logout", %{session: session} do
    Repo.query!(
      "UPDATE user_sessions SET created_at = timezone('UTC', statement_timestamp()) - interval '2 days', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second' WHERE token_hash = $1",
      [:crypto.hash(:sha256, session.token)]
    )

    {browser, csrf} = browser(session.token)
    assert redirected_to(logout(browser, csrf)) == "/"

    assert Repo.query!("SELECT count(*) FROM user_sessions WHERE token_hash = $1", [
             :crypto.hash(:sha256, session.token)
           ]).rows == [[0]]
  end

  test "invalid session credentials and asserted user IDs cannot select a user to revoke", %{
    session: session,
    user: user
  } do
    for credential <- [nil, "invalid-token", user.id] do
      {browser, csrf} = browser(credential, %{user_id: user.id})
      assert redirected_to(logout(browser, csrf)) == "/"
      assert {:ok, ^user} = UserSessions.user_for_token(session.token)
    end
  end

  defp browser(token, extra \\ %{}) do
    session = if token, do: Map.put(extra, :user_token, token), else: extra

    conn =
      build_conn()
      |> Plug.Test.init_test_session(session)
      |> put_private(:plug_skip_csrf_protection, false)
      |> get(@origin <> "/")

    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(conn, 200))
    {conn, csrf}
  end

  defp logout(conn, csrf, params \\ %{}) do
    params = if csrf, do: Map.put(params, "_csrf_token", csrf), else: params

    conn
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> post(@origin <> "/auth/logout", params)
  end
end
