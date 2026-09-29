defmodule Web.Presence do
  @moduledoc """
  Presence tracking for anonymous LiveView room participants.

  Tracks one entry per connected LiveView process on the `room:<code>` topic.
  The metadata is deliberately small and ephemeral:

      %{
        display_name: "Guest 4F2A",
        joined_at: 1_753_000_000,
        analysis_id: "analysis-1" | nil,
        path: [0, 1] | [],
        shapes: [] # board annotations, broadcast on drag end
      }

  There is no user identity yet: the web layer generates a guest name
  and the entry disappears when the LiveView process exits. When auth
  lands this becomes the place to attach a real identity.
  """

  use Phoenix.Presence,
    otp_app: :web,
    pubsub_server: Web.PubSub
end
