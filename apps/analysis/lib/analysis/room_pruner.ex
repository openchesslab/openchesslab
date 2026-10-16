defmodule Analysis.RoomPruner do
  @moduledoc """
  Periodically prune old rooms: populated rooms after 3 days without activity
  (visits reset the clock; library references are materialized first), and
  empty rooms older than 30 days as before.

  Only started in production. Uses the existing bounded PostgreSQL cleanup
  and stops any room workers removed by that cleanup.
  """

  use GenServer

  alias Analysis.Rooms

  require Logger

  @initial_delay_ms to_timeout(minute: 1)
  @interval_ms to_timeout(day: 1)
  @older_than_days 30
  @inactive_days 3
  @batch_limit 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      older_than_days: Keyword.get(opts, :older_than_days, @older_than_days),
      batch_limit: Keyword.get(opts, :batch_limit, @batch_limit),
      interval_ms: Keyword.get(opts, :interval_ms, @interval_ms)
    }

    schedule(Keyword.get(opts, :initial_delay_ms, @initial_delay_ms))
    {:ok, state}
  end

  @impl true
  def handle_info(:prune, state) do
    try do
      inactive = Rooms.prune_inactive_rooms(@inactive_days, state.batch_limit)

      if inactive != [] do
        Logger.info("Pruned #{length(inactive)} inactive rooms")
      end

      deleted = Rooms.prune_old_empty_rooms(state.older_than_days, state.batch_limit)

      if deleted != [] do
        Logger.info("Pruned #{length(deleted)} old empty rooms")
      end
    rescue
      exception ->
        Logger.error(
          "Room pruning failed: " <> Exception.format(:error, exception, __STACKTRACE__)
        )
    after
      schedule(state.interval_ms)
    end

    {:noreply, state}
  end

  defp schedule(delay_ms) do
    Process.send_after(self(), :prune, delay_ms)
  end
end
