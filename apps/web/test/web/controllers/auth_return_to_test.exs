defmodule Web.AuthReturnToTest do
  use Web.ConnCase, async: false

  alias Analysis.{Rooms, UserSessions, Users}
  alias OpenChessLab.Repo

  @origin "https://openchesslab.example"
  @lichess %{client_id: "lichess-client", redirect_uri: @origin <> "/auth/lichess/callback"}

  setup do
    settings =
      Map.new([:lichess_oauth, :lichess_oauth_request], &{&1, Application.fetch_env(:web, &1)})

    before_ids = ids()
    code = "RTRN" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    Application.put_env(:web, :lichess_oauth, @lichess)

    Application.put_env(:web, :lichess_oauth_request, fn
      :post, _, _, _ ->
        json(%{"access_token" => "lip_test", "token_type" => "Bearer", "expires_in" => 3600})

      :get, _, _, _ ->
        json(%{"id" => "return-subject"})

      :delete, _, _, _ ->
        {:ok, {{~c"HTTP/1.1", 204, ~c"OK"}, [], ""}}
    end)

    on_exit(fn ->
      Rooms.stop_room(code)
      Enum.each(ids() -- before_ids, &Users.delete/1)

      Enum.each(settings, fn
        {key, {:ok, value}} -> Application.put_env(:web, key, value)
        {key, :error} -> Application.delete_env(:web, key)
      end)
    end)

    %{code: code}
  end

  test "the room forms carry the room as the return path, home does not", ctx do
    {:ok, guest, _} = live(build_conn(), "/rooms/#{ctx.code}")
    assert has_element?(guest, "#auth-login input[name='return_to'][value='/rooms/#{ctx.code}']")

    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)

    {:ok, signed_in, _} = live(signed_in(session.token), "/rooms/#{ctx.code}")

    assert has_element?(
             signed_in,
             "#auth-logout input[name='return_to'][value='/rooms/#{ctx.code}']"
           )

    render_click(signed_in, "open-account")
    assert has_element?(signed_in, "#link-lichess input[name='return_to']")

    {:ok, home, _} = live(signed_in(session.token), "/")
    refute has_element?(home, "#auth-logout input[name='return_to']")
  end

  test "logging in from a room returns to that room", ctx do
    start = start_lichess(build_conn(), ctx.code)
    assert start.resp_cookies["_ocl_lichess_attempt"]

    result = callback(start, "lichess")
    assert redirected_to(result) == "/rooms/#{ctx.code}"
    assert {:ok, _user} = UserSessions.user_for_token(get_session(result, :user_token))
  end

  test "linking a provider from a room returns to that room", ctx do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    start = start_lichess(signed_in(session.token), ctx.code, :link)

    result = callback(start, "lichess")

    assert redirected_to(result) == "/rooms/#{ctx.code}"
    assert Analysis.Accounts.providers_for(user.id) == ["lichess"]
  end

  test "logging out from a room returns to that room", ctx do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    home = signed_in(session.token) |> put_private(:plug_skip_csrf_protection, false) |> get("/")

    [_, csrf] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))

    result =
      home
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/auth/logout", %{
        "_csrf_token" => csrf,
        "return_to" => "/rooms/#{ctx.code}"
      })

    assert redirected_to(result) == "/rooms/#{ctx.code}"
    assert :not_found = UserSessions.user_for_token(session.token)
    assert {:ok, _} = Users.get(user.id)
  end

  test "forged return paths never redirect away from the site", ctx do
    {:ok, user} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    home = signed_in(session.token) |> put_private(:plug_skip_csrf_protection, false) |> get("/")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))

    for forged <- [
          "https://evil.example",
          "//evil.example",
          "/library/some-analysis",
          "/rooms/A/B",
          "/rooms/?q=1",
          "rooms/#{ctx.code}",
          ["delete", "/rooms/#{ctx.code}"]
        ] do
      result =
        home
        |> recycle()
        |> put_private(:plug_skip_csrf_protection, false)
        |> post(@origin <> "/auth/logout", %{"_csrf_token" => csrf, "return_to" => forged})

      assert redirected_to(result) == "/"
    end
  end

  test "callback parameters cannot override the stored return path", ctx do
    start = start_lichess(build_conn(), ctx.code)

    result =
      callback(start, "lichess", %{
        "return_to" => "https://evil.example",
        "code" => "code"
      })

    assert redirected_to(result) == "/rooms/#{ctx.code}"
  end

  defp start_lichess(conn, code, intent \\ :login) do
    room =
      conn |> put_private(:plug_skip_csrf_protection, false) |> get(@origin <> "/rooms/" <> code)

    [_, csrf] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(room, 200))

    path = "/auth/lichess" <> if(intent == :link, do: "/link", else: "")

    room
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> post(@origin <> path, %{
      "_csrf_token" => csrf,
      "return_to" => "/rooms/" <> code,
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

  defp json(data),
    do:
      {:ok,
       {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"application/json"}],
        Jason.encode!(data)}}
end
