defmodule Web.HealthController do
  use Web, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
