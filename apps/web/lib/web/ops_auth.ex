defmodule Web.OpsAuth do
  @moduledoc """
  Basic auth for the ops surfaces (dashboard and status JSON).

  Credentials come from `OPS_USER`/`OPS_PASSWORD` (Fly secrets in
  production). Development falls back to a local-only default; production
  refuses to boot without `OPS_PASSWORD` (see config/runtime.exs).
  """

  import Plug.BasicAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    basic_auth(conn, username: username(), password: password())
  end

  defp username, do: System.get_env("OPS_USER") || "ops"
  defp password, do: System.get_env("OPS_PASSWORD") || "ops-local-dev"
end
