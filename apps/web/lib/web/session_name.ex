defmodule Web.SessionName do
  @moduledoc """
  Ensures every browser session carries a generated display name, created on
  the first visit. The name lives exactly as long as the session and is the
  single label shown in presence, chat and the account menu — one identity
  per session, for guests and signed-in users alike.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_session(conn, :display_name) do
      nil -> put_session(conn, :display_name, Web.DisplayName.generate())
      _name -> conn
    end
  end
end
