defmodule Web.LichessAuthControllerTest do
  use Web.ConnCase, async: false

  alias OpenChessLab.Repo
  alias Web.OAuthAttempts, as: Attempts

  @origin "https://openchesslab.example"
  @config %{client_id: "openchesslab.example", redirect_uri: @origin <> "/auth/lichess/callback"}
  @cookie "_ocl_lichess_attempt"

  setup do
    original = Application.fetch_env(:web, :lichess_oauth)
    Application.put_env(:web, :lichess_oauth, @config)

    on_exit(fn ->
      Repo.query!("DELETE FROM oauth_attempts", [])

      case original do
        {:ok, value} -> Application.put_env(:web, :lichess_oauth, value)
        :error -> Application.delete_env(:web, :lichess_oauth)
      end
    end)

    :ok
  end

  test "valid CSRF POST redirects with only trusted public PKCE parameters" do
    {browser, csrf} = browser()
    before_counts = identity_counts()

    conn =
      submit(browser, csrf, %{
        "client_id" => "attacker",
        "redirect_uri" => "https://attacker.example/callback",
        "scope" => "study:read",
        "state" => "attacker-state",
        "code_challenge" => "attacker-challenge",
        "browser_token" => "attacker-cookie",
        "user_id" => Ecto.UUID.generate()
      })

    uri = conn |> redirected_to() |> URI.parse()
    assert uri.scheme == "https"
    assert uri.host == "lichess.org"
    assert uri.path == "/oauth"
    params = URI.decode_query(uri.query)

    assert Enum.sort(Map.keys(params)) ==
             ~w(client_id code_challenge code_challenge_method redirect_uri response_type state)

    assert params["client_id"] == @config.client_id
    assert params["redirect_uri"] == @config.redirect_uri
    assert params["response_type"] == "code"
    assert params["code_challenge_method"] == "S256"
    refute params["state"] == "attacker-state"
    cookie = conn.resp_cookies[@cookie]
    assert cookie.http_only
    assert cookie.secure
    assert cookie.same_site == "Lax"
    assert cookie.max_age == 300
    assert cookie.path == "/auth/lichess"
    refute Map.has_key?(cookie, :domain)
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    assert {:ok, verifier} = Attempts.consume(params["state"], cookie.value)

    assert params["code_challenge"] ==
             Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    refute redirected_to(conn) =~ verifier
    refute redirected_to(conn) =~ cookie.value
    refute conn.resp_body =~ cookie.value
    assert before_counts == identity_counts()
  end

  test "POST without CSRF, with a wrong token or another browser's token creates no attempt" do
    {first, first_csrf} = browser()
    {second, _second_csrf} = browser()

    for {conn, token} <- [{first, nil}, {first, "invalid"}, {second, first_csrf}] do
      assert_error_sent 403, fn -> submit(conn, token) end
      assert attempt_count() == 0
    end
  end

  test "GET cannot initiate authentication" do
    assert build_conn() |> get(@origin <> "/auth/lichess") |> response(404)
    assert attempt_count() == 0
  end

  test "unconfigured login fails without a cookie, redirect or attempt" do
    Application.put_env(:web, :lichess_oauth, nil)
    {browser, csrf} = browser()
    conn = submit(browser, csrf)
    assert response(conn, 404) == "Lichess login is unavailable."
    refute Map.has_key?(conn.resp_cookies, @cookie)
    assert get_resp_header(conn, "location") == []
    assert attempt_count() == 0
  end

  test "a repeated start replaces the browser cookie with a fresh independent attempt" do
    {browser, csrf} = browser()
    first = submit(browser, csrf)
    # GET obtains the current CSRF token and recycles the actual browser cookies.
    {browser, csrf} = browser(recycle(first))
    second = submit(browser, csrf)
    first_state = redirect_params(first)["state"]
    second_state = redirect_params(second)["state"]
    refute first_state == second_state
    refute first.resp_cookies[@cookie].value == second.resp_cookies[@cookie].value

    assert {:error, :invalid_attempt} =
             Attempts.consume(first_state, second.resp_cookies[@cookie].value)

    assert {:ok, _} = Attempts.consume(second_state, second.resp_cookies[@cookie].value)
  end

  test "loopback HTTP development can use the bound cookie" do
    Application.put_env(:web, :lichess_oauth, %{
      @config
      | redirect_uri: "http://localhost:4000/auth/lichess/callback"
    })

    {browser, csrf} = browser(build_conn(), "http://localhost:4000")
    conn = submit(browser, csrf, %{}, "http://localhost:4000")
    refute conn.resp_cookies[@cookie].secure
    assert conn.resp_cookies[@cookie].http_only

    assert {:ok, _} =
             Attempts.consume(redirect_params(conn)["state"], conn.resp_cookies[@cookie].value)
  end

  test "HTTP outside matching loopback development still issues a Secure cookie" do
    for {origin, callback} <- [
          {"http://localhost:4000", @config.redirect_uri},
          {"http://remote.example", "http://localhost:4000/auth/lichess/callback"}
        ] do
      Application.put_env(:web, :lichess_oauth, %{@config | redirect_uri: callback})
      {browser, csrf} = browser(build_conn(), origin)
      conn = submit(browser, csrf, %{}, origin)
      assert conn.resp_cookies[@cookie].secure
    end
  end

  # ConnTest skips CSRF by default. Every request here explicitly enables the
  # real Plug check and obtains a token and signed session cookie from the UI.
  defp browser(conn \\ build_conn(), origin \\ @origin) do
    conn = conn |> put_private(:plug_skip_csrf_protection, false) |> get(origin <> "/")

    [_, token] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(conn, 200))

    {conn, token}
  end

  defp submit(conn, csrf, params \\ %{}, origin \\ @origin) do
    params = if csrf, do: Map.put(params, "_csrf_token", csrf), else: params

    conn
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> post(origin <> "/auth/lichess", params)
  end

  defp redirect_params(conn),
    do: conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

  defp attempt_count,
    do: Repo.query!("SELECT count(*) FROM oauth_attempts", []).rows |> hd() |> hd()

  defp identity_counts do
    Repo.query!(
      "SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM accounts), (SELECT count(*) FROM user_sessions)",
      []
    ).rows
  end
end
