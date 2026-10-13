defmodule Web.Presence do
  @moduledoc """
  Presence tracking for anonymous LiveView room participants.

  Tracks one entry per connected LiveView process on the `room:<code>` topic.
  The metadata is deliberately small and ephemeral:

      %{
        display_name: "Brave Otter 42",
        joined_at: 1_753_000_000,
        analysis_id: "analysis-1" | nil,
        path: [0, 1] | [],
        shapes: [] # board annotations, broadcast on drag end
      }

  Room participation remains anonymous: the web layer generates a display
  name independent of any provider profile, and the entry disappears when
  the LiveView process exits. Display names are labels, not authorization.
  """

  use Phoenix.Presence,
    otp_app: :web,
    pubsub_server: Web.PubSub
end
