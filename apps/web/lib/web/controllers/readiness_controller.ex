defmodule Web.ReadinessController do
  use Web, :controller

  alias Analysis.AnalysisStore
  alias Analysis.GameRecordStore
  alias Analysis.GameStore
  alias Analysis.PositionStore

  def show(conn, _params) do
    if PositionStore.ready?() and
         GameStore.ready?() and
         GameRecordStore.ready?() and
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
