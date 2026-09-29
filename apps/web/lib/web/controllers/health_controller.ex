defmodule Web.HealthController do
  @moduledoc """
  Liveness for this web node. The reply also carries the node's Fly
  region, which the UI shows next to the measured round trip.
  """

  use Web, :controller

  alias Web.NodeInfo

  def show(conn, _params) do
    json(conn, %{status: "ok", region: NodeInfo.region()})
  end
end
