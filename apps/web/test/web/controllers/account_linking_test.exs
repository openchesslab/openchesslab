defmodule Web.AccountLinkingTest do
  use Web.ConnCase, async: false

  alias Analysis.{Accounts, Users, UserSessions}
  alias OpenChessLab.Repo
  @origin "https://openchesslab.example"
  @google %{
    client_id: "google-client",
    client_secret: "private-secret",
    redirect_uri: @origin <> "/auth/google/callback"
  }
  @lichess %{client_id: "lichess-client", redirect_uri: @origin <> "/auth/lichess/callback"}

  setup do
    settings =
      Map.new(
        [:google_oauth, :google_oauth_request, :lichess_oauth, :lichess_oauth_request],
        &{&1, Application.fetch_env(:web, &1)}
      )

    before_ids = ids()
    Application.put_env(:web, :google_oauth, @google)
    Application.put_env(:web, :lichess_oauth, @lichess)

    on_exit(fn ->
      Repo.query!("DELETE FROM oauth_attempts", [])
      Enum.each(ids() -- before_ids, &Users.delete/1)

      Enum.each(settings, fn
        {key, {:ok, value}} -> Application.put_env(:web, key, value)
        {key, :error} -> Application.delete_env(:web, key)
      end)
    end)

    :ok
  end

  test "Google-only login creates one minimal identity and exposes no Lichess connection" do
    start = start(build_conn(), "google")
    params = params(start)
    assert params["scope"] == "openid"
    assert params["prompt"] == "select_account"
    refute Map.has_key?(params, "client_secret")
    refute Map.has_key?(params, "access_type")
    assert start.resp_cookies["_ocl_google_attempt"].secure
    stub_google(params["nonce"])
    completed = callback(start, "google")
    assert redirected_to(completed) == "/"
    {:ok, user} = UserSessions.user_for_token(get_session(completed, :user_token))
    assert Accounts.providers_for(user.id) == ["google"]
    assert {:ok, user.id} == Accounts.user_for_verified_identity("google", "google-subject")
    {:ok, view, _html} = live(recycle(completed), "/")
    render_click(view, "open-account")
    assert has_element?(view, "#link-lichess")
    refute has_element?(view, "#link-google")
    assert has_element?(view, "#lichess-unlinked")
    refute render(view) =~ "google-subject"
    refute render(view) =~ "private-secret"
    replay = callback(start, "google")
    assert get_session(replay, :user_token) == nil
  end

  test "link Google to Lichess; either login resolves the same user and library" do
    {:ok, user} = Users.create()
    {:ok, _} = Accounts.link_verified(user.id, "lichess", "lichess-subject")
    {:ok, old} = UserSessions.create(user.id)
    start = start(signed_in(old.token), "google", :link)
    stub_google(params(start)["nonce"])

    completed =
      callback(start, "google", %{"user_id" => Ecto.UUID.generate(), "intent" => "login"})

    assert redirected_to(completed) == "/"
    assert :not_found = UserSessions.user_for_token(old.token)
    assert {:ok, ^user} = UserSessions.user_for_token(get_session(completed, :user_token))
    assert Accounts.providers_for(user.id) == ["google", "lichess"]

    for provider <- ["google", "lichess"] do
      login = start(build_conn(), provider)
      if provider == "google", do: stub_google(params(login)["nonce"]), else: stub_lichess()
      result = callback(login, provider)
      assert {:ok, ^user} = UserSessions.user_for_token(get_session(result, :user_token))
      {:ok, _view, _html} = live(recycle(result), "/")
    end
  end

  test "Google user can explicitly link Lichess without creating another user" do
    {:ok, user_id} = Accounts.resolve_verified("google", "google-subject")
    {:ok, session} = UserSessions.create(user_id)
    before_ids = ids()
    start = start(signed_in(session.token), "lichess", :link)
    stub_lichess()
    result = callback(start, "lichess")
    assert redirected_to(result) == "/"
    assert Accounts.providers_for(user_id) == ["google", "lichess"]
    assert ids() == before_ids
  end

  test "already-owned identity is never transferred or merged and preserves the session" do
    {:ok, owner_id} = Accounts.resolve_verified("google", "google-subject")
    {:ok, other_id} = Accounts.resolve_verified("lichess", "lichess-subject")
    {:ok, old} = UserSessions.create(other_id)
    start = start(signed_in(old.token), "google", :link)
    stub_google(params(start)["nonce"])
    result = callback(start, "google")
    assert redirected_to(result) == "/"
    assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "another OpenChessLab account"
    assert get_session(result, :user_token) == old.token
    assert {:ok, ^owner_id} = Accounts.user_for_verified_identity("google", "google-subject")
    assert Accounts.providers_for(other_id) == ["lichess"]
  end

  test "anonymous linking and linking without CSRF are rejected" do
    result = start(build_conn(), "google", :link)
    assert redirected_to(result) == "/"
    refute result.resp_cookies["_ocl_google_attempt"]
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)

    assert_error_sent 403, fn ->
      signed_in(session.token)
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/auth/google/link", %{})
    end
  end

  test "revoked, expired and switched sessions cannot complete linking" do
    for change <- [:revoke, :expire, :switch] do
      {:ok, user} = Users.create()
      {:ok, session} = UserSessions.create(user.id)
      start = start(signed_in(session.token), "google", :link)
      stub_google(params(start)["nonce"])
      browser = recycle(start)

      browser =
        case change do
          :revoke ->
            UserSessions.revoke(session.token)
            browser

          :expire ->
            Repo.query!(
              "UPDATE user_sessions SET created_at = timezone('UTC', now()) - interval '2 days', expires_at = timezone('UTC', now()) - interval '1 second' WHERE user_id = $1",
              [Ecto.UUID.dump!(user.id)]
            )

            browser

          :switch ->
            {:ok, other} = Users.create()
            {:ok, replacement} = UserSessions.create(other.id)
            Plug.Test.init_test_session(browser, %{user_token: replacement.token})
        end

      result =
        get(
          browser,
          @origin <>
            "/auth/google/callback?" <>
            URI.encode_query(%{"state" => params(start)["state"], "code" => "code"})
        )

      assert redirected_to(result) == "/"
      assert Accounts.providers_for(user.id) == []
      refute_received :google_exchange
    end
  end

  test "revocation during provider exchange prevents linking at transaction boundary" do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    start = start(signed_in(session.token), "google", :link)
    stub_google(params(start)["nonce"], fn -> UserSessions.revoke(session.token) end)
    result = callback(start, "google")
    assert redirected_to(result) == "/"
    assert Accounts.providers_for(user.id) == []
  end

  test "provider mixup, denial and wrong cookie cannot authenticate" do
    start = start(build_conn(), "google")
    state = params(start)["state"]
    stub_google(params(start)["nonce"])

    mixed =
      build_conn()
      |> put_req_cookie("_ocl_lichess_attempt", start.resp_cookies["_ocl_google_attempt"].value)
      |> get(
        @origin <>
          "/auth/lichess/callback?" <> URI.encode_query(%{"state" => state, "code" => "code"})
      )

    assert get_session(mixed, :user_token) == nil
    denied = start(build_conn(), "google") |> callback("google", %{"error" => "access_denied"})
    assert get_session(denied, :user_token) == nil

    wrong =
      get(
        build_conn(),
        @origin <>
          "/auth/google/callback?" <> URI.encode_query(%{"state" => state, "code" => "code"})
      )

    assert get_session(wrong, :user_token) == nil
    refute_received :google_exchange
  end

  test "Google-only UI works with Lichess disabled and guest modal events fail closed" do
    Application.put_env(:web, :lichess_oauth, nil)
    {:ok, view, _} = live(build_conn(), "/?locale=nl")
    assert has_element?(view, "#auth-google-login", "Inloggen met Google")
    assert has_element?(view, "#auth-google-login button svg")
    refute has_element?(view, "#auth-login")

    render_click(view, "open-account", %{"user_id" => Ecto.UUID.generate()})
    assert render(view) =~ Web.I18n.t("auth.loginRequired", "nl")
    refute has_element?(view, "#link-lichess")
    refute has_element?(view, "#link-google")
  end

  test "session insertion failure rolls back linking but cannot restore the OAuth attempt" do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    start = start(signed_in(session.token), "google", :link)
    stub_google(params(start)["nonce"])

    Repo.query!(
      "ALTER TABLE user_sessions ADD CONSTRAINT link_test_reject CHECK (false) NOT VALID",
      []
    )

    try do
      assert_error_sent 500, fn -> callback(start, "google") end
    after
      Repo.query!("ALTER TABLE user_sessions DROP CONSTRAINT link_test_reject", [])
    end

    assert Accounts.providers_for(user.id) == []
    assert {:ok, ^user} = UserSessions.user_for_token(session.token)

    assert {:error, :invalid_attempt} =
             Web.OAuthAttempts.consume_context(
               params(start)["state"],
               start.resp_cookies["_ocl_google_attempt"].value
             )
  end

  test "ordinary login while signed in switches identity without implicit linking" do
    {:ok, user_id} = Accounts.resolve_verified("lichess", "lichess-subject")
    {:ok, session} = UserSessions.create(user_id)
    start = start(signed_in(session.token), "google")
    stub_google(params(start)["nonce"])
    result = callback(start, "google", %{"intent" => "link", "user_id" => user_id})
    {:ok, new_user} = UserSessions.user_for_token(get_session(result, :user_token))
    refute new_user.id == user_id
    assert Accounts.providers_for(new_user.id) == ["google"]
    assert Accounts.providers_for(user_id) == ["lichess"]
  end

  test "a revoked credential renders the guest modal variant on later events" do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    {:ok, view, _} = live(signed_in(session.token), "/")
    UserSessions.revoke(session.token)
    render_click(view, "open-account", %{"user_id" => user.id})

    assert render(view) =~ Web.I18n.t("auth.loginRequired", "en")
    refute has_element?(view, "#link-lichess")
    refute has_element?(view, "#link-google")
    assert Accounts.providers_for(user.id) == []
  end

  test "Google login initiation requires CSRF and disabled configuration issues no attempt" do
    assert_error_sent 403, fn ->
      build_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/auth/google", %{})
    end

    Application.put_env(:web, :google_oauth, nil)
    result = start(build_conn(), "google")
    assert response(result, 404) == "Login is unavailable."
    refute result.resp_cookies["_ocl_google_attempt"]
  end

  defp start(conn, provider, intent \\ :login) do
    home = conn |> put_private(:plug_skip_csrf_protection, false) |> get(@origin <> "/")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))
    path = "/auth/" <> provider <> if(intent == :link, do: "/link", else: "")

    home
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> post(@origin <> path, %{
      "_csrf_token" => csrf,
      "user_id" => Ecto.UUID.generate(),
      "subject" => "forged"
    })
  end

  defp callback(start, provider, extras \\ %{}) do
    query = Map.merge(%{"state" => params(start)["state"], "code" => "code"}, extras)

    start
    |> recycle()
    |> get(@origin <> "/auth/" <> provider <> "/callback?" <> URI.encode_query(query))
  end

  defp params(conn),
    do: conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

  defp signed_in(token), do: Plug.Test.init_test_session(build_conn(), %{user_token: token})
  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()

  defp stub_google(nonce, before_exchange \\ fn -> :ok end) do
    owner = self()

    Application.put_env(:web, :google_oauth_request, fn :post, _, _, _ ->
      send(owner, :google_exchange)
      before_exchange.()

      claims = %{
        "iss" => "https://accounts.google.com",
        "aud" => @google.client_id,
        "sub" => "google-subject",
        "nonce" => nonce,
        "iat" => System.system_time(:second),
        "exp" => System.system_time(:second) + 3600
      }

      encode = fn x -> x |> Jason.encode!() |> Base.url_encode64(padding: false) end

      json(%{
        "id_token" => encode.(%{"alg" => "RS256"}) <> "." <> encode.(claims) <> ".signature"
      })
    end)
  end

  defp stub_lichess do
    Application.put_env(:web, :lichess_oauth_request, fn
      :post, _, _, _ ->
        json(%{"access_token" => "lip_test", "token_type" => "Bearer", "expires_in" => 3600})

      :get, _, _, _ ->
        json(%{"id" => "lichess-subject"})

      :delete, _, _, _ ->
        {:ok, {{~c"HTTP/1.1", 204, ~c"OK"}, [], ""}}
    end)
  end

  defp json(data),
    do:
      {:ok,
       {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"application/json"}],
        Jason.encode!(data)}}
end
