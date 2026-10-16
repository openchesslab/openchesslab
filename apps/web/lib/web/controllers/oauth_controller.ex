defmodule Web.OAuthController do
  @moduledoc "Browser-bound login and explicit linking with fresh provider verification."
  use Web, :controller

  require Logger

  alias Analysis.{Accounts, ProviderGrants, UserSessions}
  alias OpenChessLab.Repo
  alias Web.OAuthAttempts
  alias Web.ReturnTo

  def create(conn, %{"provider" => provider} = params),
    do: start(conn, provider, :login, params)

  def link(conn, %{"provider" => provider} = params),
    do: start(conn, provider, :link, params)

  defp start(conn, provider, intent, params) do
    conn = private_response(conn)

    case config(provider) do
      nil ->
        unavailable(conn, provider)

      config ->
        context = %{
          provider: provider,
          intent: intent,
          session_hash: session_hash(get_session(conn, :user_token)),
          nonce: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
          return_to: ReturnTo.sanitize(params["return_to"])
        }

        {:ok, attempt} = OAuthAttempts.create(context)

        params =
          Map.merge(attempt.authorization_params, %{
            "response_type" => "code",
            "client_id" => config.client_id,
            "redirect_uri" => config.redirect_uri
          })

        {url, params} = authorization(provider, params, context.nonce)

        conn
        |> put_resp_cookie(cookie(provider), attempt.browser_token,
          path: path(provider),
          max_age: 300,
          http_only: true,
          secure: secure_cookie?(conn, config),
          same_site: "Lax"
        )
        |> redirect(external: url <> "?" <> URI.encode_query(params))
    end
  end

  def callback(conn, %{"provider" => provider} = params) when provider in ["lichess", "google"] do
    conn = fetch_cookies(conn)
    browser_token = conn.req_cookies[cookie(provider)]

    conn =
      conn
      |> private_response()
      |> delete_resp_cookie(cookie(provider),
        path: path(provider),
        http_only: true,
        same_site: "Lax"
      )

    case config(provider) do
      nil ->
        unavailable(conn, provider)

      config ->
        case OAuthAttempts.consume_context(params["state"], browser_token) do
          {:ok, verifier, %{provider: ^provider} = context} ->
            with :ok <- valid_context(context, get_session(conn, :user_token)),
                 false <- Map.has_key?(params, "error"),
                 {:ok, identity} <-
                   verify(provider, params["code"], verifier, context.nonce, config),
                 {:ok, session} <- complete(identity, context, get_session(conn, :user_token)) do
              store_grant(identity, session)
              Web.UserAuth.disconnect_session(get_session(conn, :user_token))
              Plug.CSRFProtection.delete_csrf_token()

              conn
              |> configure_session(renew: true)
              |> clear_session()
              |> put_session(:user_token, session.token)
              |> put_session(:live_socket_id, Web.UserAuth.live_socket_id(session.token))
              |> redirect(to: return_target(context))
            else
              {:error, :already_linked} ->
                # The consumed attempt still knows where the user started.
                failure(conn, "auth.linkConflict", return_target(context))

              _ ->
                failure(
                  conn,
                  if(provider == "lichess", do: "auth.loginFailed", else: "auth.googleFailed"),
                  ~p"/"
                )
            end

          _ ->
            failure(
              conn,
              if(provider == "lichess", do: "auth.loginFailed", else: "auth.googleFailed"),
              ~p"/"
            )
        end
    end
  end

  def callback(conn, _params), do: conn |> private_response() |> unavailable(nil)

  # The encrypted attempt binds the intent to its original browser credential.
  # A link never degrades to login if that session expires, changes or is revoked.
  defp valid_context(%{intent: :link, session_hash: expected}, token) when is_binary(expected) do
    if session_hash(token) == expected and match?({:ok, _}, UserSessions.user_for_token(token)),
      do: :ok,
      else: {:error, :invalid_session}
  end

  defp valid_context(%{intent: :login}, _), do: :ok
  defp valid_context(_, _), do: {:error, :invalid_attempt}

  defp complete(identity, context, previous_token) do
    Repo.transact(fn ->
      with {:ok, user_id} <- owner(identity, context, previous_token),
           {:ok, session} <- UserSessions.create(user_id) do
        :ok = UserSessions.revoke(previous_token)
        {:ok, session}
      end
    end)
  end

  # A Lichess access token is retained as an encrypted provider grant so the
  # user can import their games later. Grant storage must never break login;
  # the next login retries it.
  defp store_grant(%{provider: "lichess", token: token}, session) when is_binary(token) do
    with {:ok, user} <- UserSessions.user_for_token(session.token),
         :ok <- ProviderGrants.put(user.id, "lichess", token) do
      :ok
    else
      _ -> :ok
    end
  rescue
    # A missing encryption key is a deployment misconfiguration, not a login
    # failure — log it loudly, but never log the token.
    error ->
      Logger.warning("provider grant storage failed: #{Exception.message(error)}")
      :ok
  end

  defp store_grant(_identity, _session), do: :ok

  defp owner(identity, %{intent: :login}, _),
    do: Accounts.resolve_verified(identity.provider, identity.subject)

  defp owner(identity, %{intent: :link, session_hash: expected}, token) do
    # Hold the credential against concurrent logout/revocation until linking commits.
    with true <- session_hash(token) == expected,
         %{rows: [[user_id]]} <-
           Repo.query!(
             """
             SELECT user_id::text FROM user_sessions
             WHERE token_hash = $1 FOR UPDATE
             """,
             [expected],
             log: false
           ),
         {:ok, %{id: ^user_id}} <- UserSessions.user_for_token(token),
         {:ok, _} <- Accounts.link_verified(user_id, identity.provider, identity.subject) do
      {:ok, user_id}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_session}
    end
  end

  defp verify("lichess", code, verifier, _, config),
    do:
      Web.LichessOAuth.verify_code(
        code,
        verifier,
        config,
        Application.get_env(:web, :lichess_oauth_request, &:httpc.request/4)
      )

  defp verify("google", code, verifier, nonce, config),
    do:
      Web.GoogleOAuth.verify_code(
        code,
        verifier,
        nonce,
        config,
        Application.get_env(:web, :google_oauth_request, &:httpc.request/4)
      )

  defp authorization("lichess", params, _), do: {"https://lichess.org/oauth", params}

  defp authorization("google", params, nonce),
    do:
      {"https://accounts.google.com/o/oauth2/v2/auth",
       Map.merge(params, %{"scope" => "openid", "nonce" => nonce, "prompt" => "select_account"})}

  defp config("lichess"), do: Application.get_env(:web, :lichess_oauth)
  defp config("google"), do: Application.get_env(:web, :google_oauth)
  defp config(_), do: nil
  defp cookie(provider), do: "_ocl_" <> provider <> "_attempt"
  defp path(provider), do: "/auth/" <> provider
  defp session_hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)
  defp session_hash(_), do: nil

  defp unavailable(conn, "lichess"),
    do: conn |> put_status(:not_found) |> text("Lichess login is unavailable.")

  defp unavailable(conn, _), do: conn |> put_status(:not_found) |> text("Login is unavailable.")

  defp failure(conn, key, target),
    do: conn |> put_flash(:error, Web.I18n.t(key)) |> redirect(to: target)

  # The trusted return path comes only from the consumed attempt context,
  # never from callback parameters: a room start returns to that room.
  defp return_target(%{return_to: return_to}) when is_binary(return_to), do: return_to
  defp return_target(_context), do: ~p"/"

  defp private_response(conn),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

  defp secure_cookie?(conn, config) do
    callback = URI.parse(config.redirect_uri)

    not (conn.scheme == :http and conn.host in ["localhost", "127.0.0.1", "::1"] and
           callback.scheme == "http" and callback.host == conn.host)
  end
end
