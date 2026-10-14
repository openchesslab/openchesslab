defmodule Web.AccountController do
  @moduledoc """
  CSRF-protected permanent deletion of the signed-in user's own account.

  Deletion removes the internal user, its linked provider identities, every
  browser session and the personal library links. Underlying analyses and
  room content survive: room analyses carry no user reference, and detached
  personal copies await the separate orphan-cleanup policy. There is no
  recovery, merging or unlinking.
  """

  use Web, :controller

  alias Analysis.{UserSessions, Users}

  @secure_cookie Application.compile_env!(:web, :secure_session_cookie)

  # Keep in sync with the "auth.deleteWord" catalog values. Either word is
  # accepted, case-insensitively, so switching languages between rendering
  # the form and submitting it cannot trap the user.
  @confirm_words ~w(DELETE VERWIJDER)

  def delete(conn, params) do
    conn = private_response(conn)
    # Only the authenticated browser session identifies the account; request
    # parameters cannot select another user's account.
    token = get_session(conn, :user_token)

    if confirmed?(params["confirmation"]) do
      # A double submit after the first deletion commits finishes signed out.
      case Users.delete(conn.assigns.current_user.id) do
        :ok -> :ok
        :not_found -> :ok
      end

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
      |> delete_resp_cookie("_ocl_google_attempt",
        path: "/auth/google",
        secure: @secure_cookie,
        http_only: true,
        same_site: "Lax"
      )
      |> redirect(to: ~p"/")
    else
      conn
      |> put_flash(:error, Web.I18n.t("auth.deleteMismatch"))
      |> redirect(to: ~p"/")
    end
  end

  defp confirmed?(input) when is_binary(input) do
    input = input |> String.trim() |> String.upcase()
    input in @confirm_words
  end

  defp confirmed?(_), do: false

  defp private_response(conn),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
end
