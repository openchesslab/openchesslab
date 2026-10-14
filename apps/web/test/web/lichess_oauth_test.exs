defmodule Web.LichessOAuthTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias OpenChessLab.Repo
  alias Web.LichessOAuth
  alias Web.OAuthAttempts, as: Attempts

  @config %{
    client_id: "openchesslab-test",
    redirect_uri: "https://example.test/auth/lichess/callback"
  }
  @grant %{"access_token" => "lip_test_secret", "token_type" => "Bearer", "expires_in" => 3600}
  @profile %{
    "id" => "verified-id",
    "username" => "DisplayName",
    "profile" => %{"realName" => "Private Name"}
  }

  setup do
    on_exit(fn -> Repo.query!("DELETE FROM oauth_attempts", []) end)
    :ok
  end

  defmodule ProviderStub do
    @moduledoc false
    def init(options), do: options

    def call(conn, options) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(options.owner, {:http_request, conn.method, conn.request_path, body})
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")

      case {conn.method, conn.request_path} do
        {"POST", "/api/token"} ->
          conn
          |> Plug.Conn.put_resp_header("location", "/unexpected-redirect")
          |> Plug.Conn.send_resp(options.token_status, Jason.encode!(options.grant))

        {"GET", "/api/account"} ->
          Plug.Conn.send_resp(conn, 200, Jason.encode!(options.profile))

        {"DELETE", "/api/token"} ->
          Plug.Conn.send_resp(conn, 204, "")

        _ ->
          Plug.Conn.send_resp(conn, 400, "{}")
      end
    end
  end

  test "OTP HTTP client completes the exchange against a loopback provider fixture" do
    {:ok, attempt} = Attempts.create()
    request = loopback_transport(200)
    assert {:ok, %{provider: "lichess", subject: "verified-id"}} = verify(attempt, request)
    assert_receive {:http_request, "POST", "/api/token", body}
    assert URI.decode_query(body)["code"] == "liu_test_code"
    assert_receive {:http_request, "GET", "/api/account", ""}
    assert_receive {:http_request, "DELETE", "/api/token", ""}
    refute_received {:http_request, _, _, _}
  end

  test "OTP HTTP client does not follow a provider redirect" do
    {:ok, attempt} = Attempts.create()
    request = loopback_transport(302)
    assert {:error, :token_exchange_failed} = verify(attempt, request)
    assert_receive {:http_request, "POST", "/api/token", _}
    refute_received {:http_request, _, _, _}
  end

  test "consumes the attempt, exchanges the code, verifies id and revokes the grant" do
    {:ok, attempt} = Attempts.create()
    before_counts = identity_counts()
    {request, pending} = transport([response(@grant), response(@profile), revoked()])
    config = %{@config | redirect_uri: @config.redirect_uri <> "?test=a&b=c"}

    assert {:ok, %{provider: "lichess", subject: "verified-id"}} =
             verify(attempt, request, "liu_test_code", config)

    assert pending.() == []

    assert_receive {:request, :post,
                    {~c"https://lichess.org/api/token", headers, content_type, body}}

    assert headers == [{~c"accept", ~c"application/json"}]
    assert content_type == ~c"application/x-www-form-urlencoded"
    params = URI.decode_query(body)

    assert Map.keys(params) |> Enum.sort() == [
             "client_id",
             "code",
             "code_verifier",
             "grant_type",
             "redirect_uri"
           ]

    assert params["grant_type"] == "authorization_code"
    assert params["client_id"] == config.client_id
    assert params["redirect_uri"] == config.redirect_uri
    assert params["code"] == "liu_test_code"

    assert Base.url_encode64(:crypto.hash(:sha256, params["code_verifier"]), padding: false) ==
             attempt.authorization_params["code_challenge"]

    assert_receive {:request, :get, {~c"https://lichess.org/api/account", account_headers}}
    assert {~c"authorization", ~c"Bearer lip_test_secret"} in account_headers
    assert_receive {:request, :delete, {~c"https://lichess.org/api/token", ^account_headers}}
    assert {:error, :invalid_attempt} = verify(attempt, request)
    assert before_counts == identity_counts()
  end

  test "invalid state, missing cookie and expired attempts never contact Lichess" do
    {:ok, attempt} = Attempts.create()
    {request, pending} = transport([])

    assert {:error, :invalid_attempt} =
             LichessOAuth.verify_callback(
               "wrong",
               attempt.browser_token,
               "code",
               @config,
               request
             )

    assert {:error, :invalid_attempt} =
             LichessOAuth.verify_callback(
               attempt.authorization_params["state"],
               nil,
               "code",
               @config,
               request
             )

    Repo.query!(
      "UPDATE oauth_attempts SET created_at = timezone('UTC', statement_timestamp()) - interval '10 minutes', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second'",
      []
    )

    assert {:error, :invalid_attempt} = verify(attempt, request)
    assert pending.() == []
    refute_received {:request, _, _}
  end

  test "invalid codes fail without a request and cannot reuse their consumed attempt" do
    for code <- [nil, %{}, "", "code\r\nInjected", "code+invalid", String.duplicate("a", 4097)] do
      {:ok, attempt} = Attempts.create()
      {request, _} = transport([])
      assert {:error, :invalid_code} = verify(attempt, request, code)
      assert {:error, :invalid_attempt} = verify(attempt, request)
    end

    refute_received {:request, _, _}
  end

  test "trusted configuration must include a client ID and a safe absolute redirect URI" do
    for config <- [
          nil,
          %{},
          %{@config | client_id: " "},
          %{@config | redirect_uri: "/callback"},
          %{@config | redirect_uri: "http://example.test/callback"},
          %{@config | redirect_uri: "https://user:password@example.test/callback"},
          %{@config | redirect_uri: "https://example.test/callback#fragment"}
        ] do
      {:ok, attempt} = Attempts.create()
      {request, _} = transport([])
      assert {:error, :invalid_configuration} = verify(attempt, request, "code", config)
    end

    refute_received {:request, _, _}
  end

  test "supports long provider credentials and localhost development callbacks" do
    {:ok, attempt} = Attempts.create()
    grant = %{@grant | "access_token" => String.duplicate("a", 1024), "token_type" => "bearer"}
    {request, pending} = transport([response(grant), response(@profile), revoked()])

    assert {:ok, _} =
             verify(attempt, request, String.duplicate("b", 512), %{
               @config
               | redirect_uri: "http://localhost:4000/auth/lichess/callback"
             })

    assert pending.() == []
  end

  test "exchange errors, redirects, rate limits and invalid JSON fail without retries" do
    failures = [
      response(%{"error_description" => "private provider detail"}, 400),
      response(%{}, 301),
      response(%{}, 401),
      response(%{}, 429),
      response(%{}, 500),
      {:error, {:failed_connect, "private transport detail"}},
      {:ok,
       {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"text/html"}], "<html>secret</html>"}},
      response("not-json"),
      response("[]"),
      response(String.duplicate("a", 65_537))
    ]

    for failure <- failures do
      {:ok, attempt} = Attempts.create()
      {request, pending} = transport([failure])
      assert {:error, :token_exchange_failed} = verify(attempt, request)
      assert pending.() == []
      assert {:error, :invalid_attempt} = verify(attempt, request)
    end

    refute_received {:request, :get, _}
    refute_received {:request, :delete, _}
  end

  test "missing or header-unsafe access tokens are never used" do
    for grant <- [
          %{},
          %{"access_token" => nil},
          %{@grant | "access_token" => ""},
          %{@grant | "access_token" => "secret\r\nInjected: value"}
        ] do
      {:ok, attempt} = Attempts.create()
      {request, pending} = transport([response(grant)])
      assert {:error, :invalid_token_response} = verify(attempt, request)
      assert pending.() == []
    end

    refute_received {:request, :get, _}
    refute_received {:request, :delete, _}
  end

  test "a usable token is revoked even when the token metadata is invalid" do
    for grant <- [
          Map.delete(@grant, "expires_in"),
          %{@grant | "expires_in" => 0},
          %{@grant | "expires_in" => "3600"},
          %{@grant | "token_type" => "MAC"}
        ] do
      {:ok, attempt} = Attempts.create()
      {request, pending} = transport([response(grant), revoked()])
      assert {:error, :invalid_token_response} = verify(attempt, request)
      assert pending.() == []
      assert_receive {:request, :delete, _}
    end

    refute_received {:request, :get, _}
  end

  test "profile failures and missing id never fall back to username; token is still revoked" do
    for profile <- [
          response(%{"username" => "unverified-fallback"}),
          response(%{"id" => " "}),
          response(%{"id" => 42}),
          response(%{}, 401),
          response(%{}, 302),
          response(%{}, 429),
          {:error, :timeout},
          response("invalid-json")
        ] do
      {:ok, attempt} = Attempts.create()
      {request, pending} = transport([response(@grant), profile, revoked()])
      assert {:error, :account_verification_failed} = verify(attempt, request)
      assert pending.() == []
      assert_receive {:request, :delete, _}
    end
  end

  test "verification success requires confirmed revocation" do
    for failure <- [response(%{}, 302), response(%{}, 429), {:error, :timeout}] do
      {:ok, attempt} = Attempts.create()
      {request, pending} = transport([response(@grant), response(@profile), failure])
      assert {:error, :revocation_failed} = verify(attempt, request)
      assert pending.() == []
      assert {:error, :invalid_attempt} = verify(attempt, request)
    end
  end

  test "transport exits are sanitized without logging provider secrets" do
    {:ok, attempt} = Attempts.create()
    request = fn _, _, _, _ -> exit({:transport_error, "sensitive_code_and_token"}) end

    log =
      capture_log(fn ->
        assert {:error, :token_exchange_failed} = verify(attempt, request)
      end)

    refute log =~ "sensitive_code_and_token"
  end

  defp verify(attempt, request, code \\ "liu_test_code", config \\ @config) do
    LichessOAuth.verify_callback(
      attempt.authorization_params["state"],
      attempt.browser_token,
      code,
      config,
      request
    )
  end

  defp loopback_transport(token_status) do
    ref = make_ref()
    options = %{owner: self(), grant: @grant, profile: @profile, token_status: token_status}
    {:ok, _} = Plug.Cowboy.http(ProviderStub, options, ref: ref, port: 0, ip: {127, 0, 0, 1})
    on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    port = :ranch.get_port(ref)

    # Only the test seam rewrites the origin. Production has fixed HTTPS endpoints.
    fn method, payload, http_options, options ->
      path = payload |> elem(0) |> to_string() |> URI.parse() |> Map.fetch!(:path)
      local_url = String.to_charlist("http://127.0.0.1:#{port}" <> path)
      :httpc.request(method, put_elem(payload, 0, local_url), http_options, options)
    end
  end

  defp response(data, status \\ 200) do
    body = if is_binary(data), do: data, else: Jason.encode!(data)

    {:ok,
     {{~c"HTTP/1.1", status, ~c"Response"},
      [{~c"content-type", ~c"application/json; charset=utf-8"}], body}}
  end

  defp revoked, do: {:ok, {{~c"HTTP/1.1", 204, ~c"No Content"}, [], ""}}

  defp transport(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    owner = self()

    request = fn method, payload, http_options, options ->
      assert http_options[:ssl][:verify] == :verify_peer
      assert is_list(http_options[:ssl][:cacerts]) and http_options[:ssl][:cacerts] != []
      assert is_function(http_options[:ssl][:customize_hostname_check][:match_fun], 2)
      assert http_options[:autoredirect] == false
      assert http_options[:autoretry] == 0
      assert http_options[:timeout] == 10_000
      assert http_options[:connect_timeout] == 5_000
      assert options[:body_format] == :binary
      assert options[:max_body_size] == 65_536
      assert options[:max_header_size] == 8192
      send(owner, {:request, method, payload})

      Agent.get_and_update(agent, fn
        [response | rest] -> {response, rest}
        [] -> {:unexpected_request, []}
      end)
    end

    {request, fn -> Agent.get(agent, & &1) end}
  end

  defp identity_counts do
    Repo.query!(
      "SELECT (SELECT count(*) FROM users), (SELECT count(*) FROM accounts), (SELECT count(*) FROM user_sessions)",
      []
    ).rows
  end
end
