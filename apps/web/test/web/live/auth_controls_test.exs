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

      assert has_element?(
               view,
               "#account-menu #auth-login[action='/auth/lichess'][method='post']",
               label
             )

      assert has_element?(view, "#auth-login button svg")
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
    refute has_element?(guest, "#account-menu")

    for path <- ["/", "/rooms/#{context.code}"] do
      conn = Plug.Test.init_test_session(build_conn(), %{user_token: context.session.token})
      {:ok, view, html} = live(conn, path <> "?locale=nl")
      assert has_element?(view, "#auth-logout[action='/auth/logout'][method='post']", "Uitloggen")
      assert has_element?(view, "#account-menu #personal-library-button svg", "")
      assert has_element?(view, "#account-menu #personal-library-button", "Mijn bibliotheek")
      assert has_element?(view, "#account-menu #linked-accounts-button", "Gekoppelde accounts")
      assert has_element?(view, "#account-menu #linked-accounts-button svg")
      assert has_element?(view, "#auth-logout button svg")
      assert has_element?(view, "#account-menu summary[title='Account']")
      assert has_element?(view, "#account-badge")
      refute has_element?(view, "#auth-login")
      refute html =~ context.user.id
      refute html =~ context.session.token
    end
  end

  test "the account menu shows the session identity badge and name", %{
    session: session
  } do
    # The first visit assigns a session name; the account menu shows it.
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_token: session.token})
      |> get("/")

    name = get_session(conn, :display_name)

    {:ok, view, _html} = live(recycle(conn), "/")

    # The button is the initials badge with the name's deterministic color.
    assert has_element?(view, "#account-badge", Web.DisplayName.initials(name))

    badge_style =
      view
      |> element("#account-badge")
      |> render()
      |> then(fn html -> Regex.run(~r/background-color: ([^"]+)/, html) end)

    assert [_, "hsl(" <> _hue] = badge_style

    # The dropdown header carries the full name and avatar, with a help icon
    # explaining the generated label.
    assert has_element?(view, "#account-identity", name)
    assert has_element?(view, "#account-identity", "Signed in")
    assert has_element?(view, "#account-name-help[title*='generated']")
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

    state =
      started
      |> redirected_to()
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    denial =
      URI.encode_query(%{
        "state" => state,
        "error" => "access_denied",
        "error_description" => "private-detail"
      })

    denied =
      started
      |> recycle()
      |> get("/auth/lichess/callback?" <> denial)

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

  test "one theme button cycles saved preferences on home and rooms", %{code: code} do
    for path <- ["/", "/rooms/#{code}"] do
      conn = put_req_cookie(build_conn(), "_ocl_theme", "dark")
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#theme-cycle[phx-value-theme='system']")

      assert view
             |> render()
             |> LazyHTML.from_document()
             |> LazyHTML.query("button[phx-click='set-theme']")
             |> LazyHTML.attribute("id") == ["theme-cycle"]

      for {current, next} <- [{"dark", "system"}, {"system", "light"}, {"light", "dark"}] do
        assert has_element?(view, "#app-shell[data-theme='#{current}']")
        view |> element("#theme-cycle") |> render_click()
        assert_push_event(view, "set-theme", %{theme: ^next})
        assert has_element?(view, "#app-shell[data-theme='#{next}']")
      end
    end
  end

  test "Help and piece selection belong to the room workspace in both languages", %{code: code} do
    for locale <- ["en", "nl"] do
      {:ok, home, _} = live(build_conn(), "/?locale=" <> locale)

      for selector <- ["#help-menu", "#piece-set-desktop-form", "#piece-set-menu"] do
        refute has_element?(home, selector)
      end

      render_click(home, "open-shortcuts", %{})
      render_click(home, "open-tour", %{})
      refute has_element?(home, "[role='dialog']")

      path = "/rooms/#{code}"
      {:ok, view, _} = live(build_conn(), path <> "?locale=" <> locale)
      assert has_element?(view, "#piece-set-desktop-form")
      assert has_element?(view, "#piece-set-menu")
      assert has_element?(view, "#help-menu summary[title='Help']")
      assert has_element?(view, "#help-menu summary svg")
      view |> element("#help-menu #help-shortcuts") |> render_click()
      assert has_element?(view, "[role='dialog'][aria-labelledby='shortcuts-title']")
      render_click(view, "close-modal", %{})
      view |> element("#help-menu #help-tour") |> render_click()
      assert has_element?(view, "[role='dialog'][aria-labelledby='tour-title']")
    end
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
