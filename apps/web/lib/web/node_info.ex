defmodule Web.NodeInfo do
  @moduledoc """
  This node's Fly region (`FLY_REGION`), or `"local"` outside Fly (dev,
  tests).

  The region is sent to clients in the health check and in the room
  join reply, so the UI can show which region it is talking to and how
  far the round trip is.
  """

  @spec region() :: String.t()
  def region do
    System.get_env("FLY_REGION") || "local"
  end
end
