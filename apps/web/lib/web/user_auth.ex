defmodule Web.UserAuth do
  @moduledoc """
  Resolve optional browser authentication from revocable PostgreSQL credentials.

  The session must come from Phoenix's protected cookie or LiveView session.
  Request parameters and asserted User IDs are never authentication. Public
  views remain guest-accessible; private views still need explicit authorization.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Analysis.UserSessions

  def init(opts), do: opts

  def call(conn, _opts) do
    token = Plug.Conn.get_session(conn, :user_token)
    user = resolve(token)

    conn =
      if user do
        Plug.Conn.put_session(conn, :live_socket_id, live_socket_id(token))
      else
        Plug.Conn.delete_session(conn, :live_socket_id)
      end

    Plug.Conn.assign(conn, :current_user, user)
  end

  @doc "A session-specific Phoenix transport topic, containing no bearer credential."
  def live_socket_id(token) when is_binary(token) and byte_size(token) == 43 do
    "user_sessions:" <> Base.url_encode64(:crypto.hash(:sha256, token), padding: false)
  end

  def live_socket_id(_token), do: nil

  @doc "Disconnect a browser credential only after its revocation has committed."
  def disconnect_session(token) do
    if topic = live_socket_id(token) do
      Web.Endpoint.broadcast(topic, "disconnect", %{})
    end

    :ok
  end

  def on_mount(:default, _params, session, socket) do
    token = session["user_token"]

    socket =
      socket
      |> assign(:current_user, resolve(token))
      |> assign(:login_enabled, not is_nil(Application.get_env(:web, :lichess_oauth)))
      |> attach_hook(:refresh_authentication, :handle_event, fn _event, _params, socket ->
        # Revalidate before the view's handler. A mount-time User assign is
        # insufficient after expiry/logout. Keep the credential out of assigns.
        {:cont, assign(socket, :current_user, resolve(token))}
      end)

    {:cont, socket}
  end

  defp resolve(token) do
    case UserSessions.user_for_token(token) do
      {:ok, user} -> user
      :not_found -> nil
    end
  end
end
