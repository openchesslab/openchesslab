defmodule Web.ReadinessController do
  use Web, :controller

  alias Analysis.GameStore
  alias Analysis.PositionStore

  def show(conn, _params) do
    if PositionStore.ready?() and GameStore.ready?() do
      json(conn, %{status: "ready"})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable"})
    end
  end
end
