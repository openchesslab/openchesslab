defmodule Web.SessionController do
  @moduledoc "CSRF-protected logout of the current browser's server-side session."

  use Web, :controller

  alias Analysis.UserSessions

  @secure_cookie Application.compile_env!(:web, :secure_session_cookie)

  def delete(conn, _params) do
    # Only the protected browser session supplies the credential. Request
    # parameters cannot select another user's session or trigger revoke_all.
    token = get_session(conn, :user_token)
    :ok = UserSessions.revoke(token)
    :ok = Web.UserAuth.disconnect_session(token)
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> delete_resp_cookie("_web_key",
      path: "/",
      secure: @secure_cookie,
      http_only: true,
      same_site: "Lax"
    )
    |> delete_resp_cookie("_ocl_lichess_attempt",
      path: "/auth/lichess",
      secure: @secure_cookie,
      http_only: true,
      same_site: "Lax"
    )
    |> put_resp_header("cache-control", "no-store")
    |> delete_resp_cookie("_ocl_google_attempt",
      path: "/auth/google",
      secure: @secure_cookie,
      http_only: true,
      same_site: "Lax"
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> redirect(to: ~p"/")
  end
end
