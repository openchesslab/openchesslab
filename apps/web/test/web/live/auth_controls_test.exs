defmodule Web.AuthControlsTest do
  use Web.ConnCase, async: false

  alias Analysis.Rooms
  alias Analysis.Users
  alias Analysis.UserSessions

  @config %{
    client_id: "openchesslab.example",
    redirect_uri: "https://openchesslab.example/auth/lichess/callback"
  }

  setup do
    original = Application.fetch_env(:web, :lichess_oauth)
    Application.put_env(:web, :lichess_oauth, @config)
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    code = "UI" <> Base.encode16(:crypto.strong_rand_bytes(4))
    {:ok, _room} = Rooms.start_room(code)

    on_exit(fn ->
      Users.delete(user.id)
      Rooms.stop_room(code)

      case original do
        {:ok, value} -> Application.put_env(:web, :lichess_oauth, value)
        :error -> Application.delete_env(:web, :lichess_oauth)
      end
    end)

    %{session: session, user: user, code: code}
  end

  test "guests see native login forms on both public routes in either language", %{code: code} do
    for path <- ["/", "/rooms/#{code}"],
        {locale, label} <- [{"en", "Log in with Lichess"}, {"nl", "Inloggen met Lichess"}] do
      {:ok, view, _html} = live(build_conn(), path <> "?locale=" <> locale)
      assert has_element?(view, "#auth-login[action='/auth/lichess'][method='post']", label)
      assert has_element?(view, "#auth-login input[name='_csrf_token']")
      refute has_element?(view, "#auth-login[phx-submit]")
      refute has_element?(view, "#auth-logout")
    end
  end

  test "disabled login stays hidden while authenticated logout remains available", context do
    Application.put_env(:web, :lichess_oauth, nil)
    {:ok, guest, _html} = live(build_conn(), "/")
    refute has_element?(guest, "#auth-login")
    refute has_element?(guest, "#auth-logout")

    for path <- ["/", "/rooms/#{context.code}"] do
      conn = Plug.Test.init_test_session(build_conn(), %{user_token: context.session.token})
      {:ok, view, html} = live(conn, path <> "?locale=nl")
      assert has_element?(view, "#auth-logout[action='/auth/logout'][method='post']", "Uitloggen")
      refute has_element?(view, "#auth-login")
      refute html =~ context.user.id
      refute html =~ context.session.token
    end
  end

  test "revocation updates the header on the next event", %{session: session} do
    conn = Plug.Test.init_test_session(build_conn(), %{user_token: session.token})
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#auth-logout", "Log out")
    UserSessions.revoke(session.token)
    render_click(view, "set-locale", %{"locale" => "nl"})
    refute has_element?(view, "#auth-logout")
    assert has_element?(view, "#auth-login", "Inloggen met Lichess")
  end

  test "the rendered login form passes real CSRF checks and failures are visible" do
    home = get(build_conn(), "/?locale=nl")
    csrf = form_csrf(home, "auth-login")

    started =
      home
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/auth/lichess", %{"_csrf_token" => csrf})

    assert redirected_to(started) =~ "https://lichess.org/oauth?"

    denied =
      started
      |> recycle()
      |> get("/auth/lichess/callback?error=access_denied&error_description=private-detail")

    {:ok, view, html} = live(get(recycle(denied), "/"))
    assert has_element?(view, "#app-error[role='alert']", "Inloggen met Lichess is mislukt.")
    refute html =~ "private-detail"
    assert has_element?(view, "#auth-login")
  end

  test "the rendered logout form revokes the session with real CSRF protection", %{
    session: session
  } do
    home =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: session.token})
      |> get("/")

    logged_out =
      home
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/auth/logout", %{"_csrf_token" => form_csrf(home, "auth-logout")})

    assert redirected_to(logged_out) == "/"
    assert :not_found = UserSessions.user_for_token(session.token)
    {:ok, view, _html} = live(get(recycle(logged_out), "/"))
    assert has_element?(view, "#auth-login")
    refute has_element?(view, "#auth-logout")
  end

  defp form_csrf(conn, id) do
    [token] =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("##{id} input[name='_csrf_token']")
      |> LazyHTML.attribute("value")

    token
  end
end
