defmodule Web.ReadinessController do
  use Web, :controller

  alias Analysis.AnalysisStore
  alias OpenChessLab.Repo

  def show(conn, _params) do
    if Repo.ready?() and
         AnalysisStore.ready?() do
      json(
        conn,
        %{status: "ready"}
      )
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable"})
    end
  end
end
