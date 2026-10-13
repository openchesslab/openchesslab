defmodule Web.LichessAuthController do
  @moduledoc "Browser-bound Lichess login with CSRF initiation and one-time PKCE callbacks."

  use Web, :controller

  alias Analysis.Accounts
  alias Analysis.UserSessions
  alias OpenChessLab.Repo
  alias Web.LichessOAuth
  alias Web.LichessOAuthAttempts

  @attempt_cookie "_ocl_lichess_attempt"
  @cookie_path "/auth/lichess"

  def create(conn, _params) do
    conn = private_response(conn)

    case Application.get_env(:web, :lichess_oauth) do
      nil ->
        conn |> put_status(:not_found) |> text("Lichess login is unavailable.")

      config ->
        {:ok, attempt} = LichessOAuthAttempts.create()

        params =
          Map.merge(attempt.authorization_params, %{
            "response_type" => "code",
            "client_id" => config.client_id,
            "redirect_uri" => config.redirect_uri
          })

        conn
        |> put_resp_cookie(@attempt_cookie, attempt.browser_token,
          path: @cookie_path,
          max_age: 300,
          http_only: true,
          secure: secure_cookie?(conn, config),
          same_site: "Lax"
        )
        |> redirect(external: "https://lichess.org/oauth?" <> URI.encode_query(params))
    end
  end

  def callback(conn, params) do
    conn = fetch_cookies(conn)
    browser_token = conn.req_cookies[@attempt_cookie]

    conn =
      conn
      |> private_response()
      |> delete_resp_cookie(@attempt_cookie,
        path: @cookie_path,
        http_only: true,
        same_site: "Lax"
      )

    case Application.get_env(:web, :lichess_oauth) do
      nil ->
        conn |> put_status(:not_found) |> text("Lichess login is unavailable.")

      config ->
        with {:ok, identity} <- verify_identity(params, browser_token, config),
             {:ok, session} <- issue_session(identity, get_session(conn, :user_token)) do
          # Publish only after the transaction commits, never on a failed login.
          Web.UserAuth.disconnect_session(get_session(conn, :user_token))
          Plug.CSRFProtection.delete_csrf_token()

          conn
          |> configure_session(renew: true)
          |> clear_session()
          |> put_session(:user_token, session.token)
          |> put_session(:live_socket_id, Web.UserAuth.live_socket_id(session.token))
          |> redirect(to: ~p"/")
        else
          {:error, _reason} ->
            conn
            |> put_flash(:error, Web.I18n.t("auth.loginFailed"))
            |> redirect(to: ~p"/")
        end
    end
  end

  defp verify_identity(%{"error" => _error} = params, browser_token, _config) do
    LichessOAuthAttempts.cancel(params["state"], browser_token)
    {:error, :provider_denied}
  end

  defp verify_identity(params, browser_token, config) do
    # Trusted HTTP test seam; never supplied by request parameters.
    request = Application.get_env(:web, :lichess_oauth_request, &:httpc.request/4)
    LichessOAuth.verify_callback(params["state"], browser_token, params["code"], config, request)
  end

  defp issue_session(identity, previous_token) do
    Repo.transact(fn ->
      with {:ok, user_id} <- Accounts.resolve_verified(identity.provider, identity.subject),
           {:ok, session} <- UserSessions.create(user_id) do
        :ok = UserSessions.revoke(previous_token)
        {:ok, session}
      end
    end)
  end

  defp private_response(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
  end

  # Production configuration requires HTTPS. The exception supports only a
  # loopback HTTP browser with a loopback HTTP callback in local development.
  defp secure_cookie?(conn, config) do
    callback = URI.parse(config.redirect_uri)

    not (conn.scheme == :http and conn.host in ["localhost", "127.0.0.1", "::1"] and
           callback.scheme == "http" and callback.host == conn.host)
  end
end
