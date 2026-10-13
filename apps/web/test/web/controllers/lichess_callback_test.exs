defmodule Web.LichessCallbackTest do
  use Web.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Analysis.Accounts
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo
  alias Web.LichessOAuthAttempts, as: Attempts

  @origin "https://openchesslab.example"
  @config %{client_id: "openchesslab.example", redirect_uri: @origin <> "/auth/lichess/callback"}
  @cookie "_ocl_lichess_attempt"
  @subject "private-verified-lichess-id"

  setup do
    settings =
      Map.new([:lichess_oauth, :lichess_oauth_request], &{&1, Application.fetch_env(:web, &1)})

    before_ids = user_ids()
    Application.put_env(:web, :lichess_oauth, @config)

    on_exit(fn ->
      Repo.query!("DELETE FROM lichess_oauth_attempts", [])
      Enum.each(user_ids() -- before_ids, &Users.delete/1)

      Enum.each(settings, fn
        {key, {:ok, value}} -> Application.put_env(:web, key, value)
        {key, :error} -> Application.delete_env(:web, key)
      end)
    end)

    :ok
  end

  test "verified callback creates HMAC account and an encrypted revocable browser session" do
    stub_success()

    start =
      build_conn()
      |> put_req_cookie("_ocl_theme", "dark")
      |> put_req_cookie("_ocl_locale", "nl")
      |> start_login()

    completed = callback(start, %{"user_id" => Ecto.UUID.generate(), "subject" => "unverified"})
    assert redirected_to(completed) == "/"
    assert cleared_attempt?(completed)
    assert get_resp_header(completed, "cache-control") == ["no-store"]
    assert get_resp_header(completed, "referrer-policy") == ["no-referrer"]

    browser = get(recycle(completed), @origin <> "/")
    root = browser |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("html")
    assert LazyHTML.attribute(root, "lang") == ["nl"]
    assert LazyHTML.attribute(root, "data-theme") == ["dark"]
    assert html_response(browser, 200) =~ "Kamer aanmaken"
    token = get_session(browser, :user_token)
    assert {:ok, user} = UserSessions.user_for_token(token)
    assert {:ok, user.id} == Accounts.user_for_verified_identity("lichess", @subject)
    assert :not_found = Accounts.user_for_verified_identity("lichess", "unverified")

    assert Enum.sort(Map.keys(get_session(browser))) == [
             "_csrf_token",
             "live_socket_id",
             "localize_locale",
             "ui_theme",
             "user_token"
           ]

    cookie = completed.resp_cookies["_web_key"]
    assert cookie.http_only
    assert cookie.same_site == "Lax"
    assert cookie.max_age == 86_400
    refute cookie.value =~ token
    refute cookie.value =~ @subject
    refute completed.resp_body =~ token
    assert_provider_requests(start)

    assert :ok = UserSessions.revoke(token)
    assert :not_found = UserSessions.user_for_token(token)
  end

  test "success reuses the account owner, revokes the old session and clears fixed session data" do
    {:ok, owner} = Users.create()
    {:ok, _account} = Accounts.link_verified(owner.id, "lichess", @subject)
    {:ok, old} = UserSessions.create(owner.id)

    conn =
      Plug.Test.init_test_session(build_conn(), %{
        user_token: old.token,
        user_id: "fixed",
        extra: "fixed"
      })

    stub_success()
    start = start_login(conn)
    old_topic = get_session(start, :live_socket_id)
    Web.Endpoint.subscribe(old_topic)
    old_csrf = get_session(start, :_csrf_token)
    completed = callback(start)
    assert_receive %Phoenix.Socket.Broadcast{topic: ^old_topic, event: "disconnect"}
    new_topic = get_session(completed, :live_socket_id)
    refute new_topic == old_topic
    assert new_topic == Web.UserAuth.live_socket_id(get_session(completed, :user_token))
    browser = get(recycle(completed), @origin <> "/")
    token = get_session(browser, :user_token)

    refute token == old.token
    assert :not_found = UserSessions.user_for_token(old.token)
    assert {:ok, %{id: id}} = UserSessions.user_for_token(token)
    assert id == owner.id
    refute get_session(browser, :_csrf_token) == old_csrf
    assert get_session(browser, :user_id) == nil
    assert get_session(browser, :extra) == nil
    assert user_ids() |> Enum.count(&(&1 == owner.id)) == 1
  end

  test "logging into another provider identity replaces login without linking or merging users" do
    {:ok, previous_user} = Users.create()
    {:ok, previous} = UserSessions.create(previous_user.id)
    stub_success()
    start = start_login(Plug.Test.init_test_session(build_conn(), %{user_token: previous.token}))
    completed = callback(start)
    assert {:ok, owner_id} = Accounts.user_for_verified_identity("lichess", @subject)
    refute owner_id == previous_user.id
    assert Accounts.providers_for(previous_user.id) == []
    assert :not_found = UserSessions.user_for_token(previous.token)

    assert {:ok, %{id: ^owner_id}} =
             UserSessions.user_for_token(get_session(completed, :user_token))
  end

  test "missing, wrong and query-supplied browser cookies fail before provider contact" do
    stub([])
    start = start_login()
    state = state(start)
    before_counts = counts()

    for conn <- [build_conn(), put_req_cookie(build_conn(), @cookie, "wrong-cookie")] do
      result =
        callback(conn, %{"state" => state, "browser_token" => start.resp_cookies[@cookie].value})

      assert redirected_to(result) == "/"
      assert cleared_attempt?(result)
      assert get_session(result, :user_token) == nil
    end

    assert before_counts == counts()
    refute_received {:provider_request, _, _}
    assert {:ok, _} = Attempts.consume(state, start.resp_cookies[@cookie].value)
  end

  test "expired and replayed callbacks cannot issue sessions" do
    stub_success()
    start = start_login()
    completed = callback(start)
    after_counts = counts()
    replay = callback(start)
    assert get_session(replay, :user_token) == nil
    assert after_counts == counts()
    assert_provider_requests(start)

    expired = start_login()

    Repo.query!(
      "UPDATE lichess_oauth_attempts SET created_at = timezone('UTC', statement_timestamp()) - interval '10 minutes', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second'",
      []
    )

    failed = callback(expired)
    assert cleared_attempt?(failed)
    assert get_session(failed, :user_token) == nil
    assert after_counts == counts()
    refute_received {:provider_request, _, _}
    assert get_session(completed, :user_token) != nil
  end

  test "provider denial consumes the bound attempt without exchange or reflecting its description" do
    stub([])
    start = start_login()

    result =
      callback(start, %{
        "error" => "access_denied",
        "error_description" => "private-provider-detail"
      })

    assert redirected_to(result) == "/"
    assert cleared_attempt?(result)

    assert Phoenix.Flash.get(result.assigns.flash, :error) ==
             "Lichess login failed. Please try again."

    assert {:error, :invalid_attempt} =
             Attempts.consume(state(start), start.resp_cookies[@cookie].value)

    assert get_session(result, :user_token) == nil
    refute_received {:provider_request, _, _}
  end

  test "provider exchange, verification and revocation failures preserve an existing session" do
    {:ok, user} = Users.create()
    {:ok, previous} = UserSessions.create(user.id)

    for responses <- [
          [{:error, :timeout}],
          [grant(), json(%{"username" => "unverified"}), revoked()],
          [grant(), json(%{"id" => @subject}), {:error, :timeout}]
        ] do
      stub(responses)
      conn = Plug.Test.init_test_session(build_conn(), %{user_token: previous.token})
      start = start_login(conn)
      Web.Endpoint.subscribe(get_session(start, :live_socket_id))
      before_counts = counts()
      failed = callback(start)
      assert cleared_attempt?(failed)
      assert get_session(failed, :user_token) == previous.token
      assert {:ok, ^user} = UserSessions.user_for_token(previous.token)
      assert before_counts == counts()
      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}

      assert {:error, :invalid_attempt} =
               Attempts.consume(state(start), start.resp_cookies[@cookie].value)
    end
  end

  test "database failure rolls back the new user and account without restoring the attempt" do
    {:ok, user} = Users.create()
    {:ok, previous} = UserSessions.create(user.id)
    stub_success()
    start = start_login(Plug.Test.init_test_session(build_conn(), %{user_token: previous.token}))
    Web.Endpoint.subscribe(get_session(start, :live_socket_id))
    before_counts = counts()

    Repo.query!(
      "ALTER TABLE user_sessions ADD CONSTRAINT callback_test_reject CHECK (false) NOT VALID",
      []
    )

    try do
      assert_error_sent 500, fn -> callback(start) end
    after
      Repo.query!("ALTER TABLE user_sessions DROP CONSTRAINT callback_test_reject", [])
    end

    assert before_counts == counts()
    assert {:ok, ^user} = UserSessions.user_for_token(previous.token)
    refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}

    assert {:error, :invalid_attempt} =
             Attempts.consume(state(start), start.resp_cookies[@cookie].value)
  end

  test "disabled callback clears the pending cookie without contacting the provider" do
    stub([])
    start = start_login()
    Application.put_env(:web, :lichess_oauth, nil)
    result = callback(start)
    assert response(result, 404) == "Lichess login is unavailable."
    assert cleared_attempt?(result)
    refute_received {:provider_request, _, _}
  end

  test "callback logs filter authorization codes and provider details" do
    stub([])
    start = start_login()
    level = Logger.level()

    try do
      Logger.configure(level: :debug)

      log =
        capture_log(fn ->
          callback(start, %{
            "code" => "liu_private_code",
            "error" => "access_denied",
            "error_description" => "private-provider-detail"
          })
        end)

      assert log =~ "[FILTERED]"
      refute log =~ "liu_private_code"
      refute log =~ "private-provider-detail"
      refute log =~ start.resp_cookies[@cookie].value
    after
      Logger.configure(level: level)
    end
  end

  test "production declares Secure browser sessions independently of proxy scheme" do
    path = Path.expand("../../../../../config/config.exs", __DIR__)

    assert Config.Reader.read!(path, env: :prod, target: :host)[:web][:secure_session_cookie] ==
             true
  end

  defp start_login(conn \\ build_conn()) do
    home = conn |> put_private(:plug_skip_csrf_protection, false) |> get(@origin <> "/")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))

    home
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> post(@origin <> "/auth/lichess", %{"_csrf_token" => csrf})
  end

  defp callback(conn, params \\ %{}) do
    params = Map.merge(%{"state" => state(conn), "code" => "liu_test_code"}, params)

    conn
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> get(@origin <> "/auth/lichess/callback?" <> URI.encode_query(params))
  end

  defp state(%{status: 302} = conn),
    do:
      conn
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

  defp state(_conn), do: "missing-state"
  defp cleared_attempt?(conn), do: conn.resp_cookies[@cookie].max_age == 0

  defp user_ids,
    do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> Enum.map(&hd/1)

  defp counts,
    do:
      Repo.query!(
        "SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM accounts), (SELECT count(*) FROM user_sessions)",
        []
      ).rows

  defp stub_success,
    do:
      stub([
        grant(),
        json(%{
          "id" => @subject,
          "username" => "PrivateName",
          "profile" => %{"realName" => "PrivateName"}
        }),
        revoked()
      ])

  defp grant,
    do:
      json(%{
        "access_token" => "lip_private_token",
        "token_type" => "Bearer",
        "expires_in" => 3600
      })

  defp json(data),
    do:
      {:ok,
       {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"application/json"}],
        Jason.encode!(data)}}

  defp revoked, do: {:ok, {{~c"HTTP/1.1", 204, ~c"No Content"}, [], ""}}

  defp stub(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    owner = self()

    request = fn method, payload, _http, _options ->
      send(owner, {:provider_request, method, payload})
      Agent.get_and_update(agent, fn [response | rest] -> {response, rest} end)
    end

    Application.put_env(:web, :lichess_oauth_request, request)
  end

  defp assert_provider_requests(start) do
    assert_receive {:provider_request, :post, {~c"https://lichess.org/api/token", _, _, body}}
    params = URI.decode_query(body)
    assert params["client_id"] == @config.client_id
    assert params["redirect_uri"] == @config.redirect_uri
    assert params["code"] == "liu_test_code"

    challenge =
      start
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("code_challenge")

    assert challenge ==
             Base.url_encode64(:crypto.hash(:sha256, params["code_verifier"]), padding: false)

    assert_receive {:provider_request, :get, {~c"https://lichess.org/api/account", _}}
    assert_receive {:provider_request, :delete, {~c"https://lichess.org/api/token", _}}
  end
end
