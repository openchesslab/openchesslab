defmodule Web.LichessAuthController do
  @moduledoc "CSRF-protected initiation of browser-bound Lichess login."

  use Web, :controller

  alias Web.LichessOAuthAttempts

  @attempt_cookie "_ocl_lichess_attempt"
  @cookie_path "/auth/lichess"

  def create(conn, _params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

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

  # Production configuration requires HTTPS. The exception supports only a
  # loopback HTTP browser with a loopback HTTP callback in local development.
  defp secure_cookie?(conn, config) do
    callback = URI.parse(config.redirect_uri)

    not (conn.scheme == :http and conn.host in ["localhost", "127.0.0.1", "::1"] and
           callback.scheme == "http" and callback.host == conn.host)
  end
end
