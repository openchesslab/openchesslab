defmodule Web.LichessSync.Worker do
  @moduledoc """
  Schedules the opt-in Lichess library sync: every 15 minutes for all enabled
  grants, and once shortly after a user enables it (`kick/1`). Thin wrapper;
  the logic lives in `Web.LichessSync`.
  """

  use GenServer

  @interval_ms :timer.minutes(15)
  @kick_delay_ms 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Sync this user soon (after they enabled sync)."
  @spec kick(String.t()) :: :ok
  def kick(user_id) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:kick, user_id})
    end
  end

  @impl true
  def init(_opts) do
    schedule_sync()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:kick, user_id}, state) do
    Process.send_after(self(), {:sync_user, user_id}, @kick_delay_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync, state) do
    Web.LichessSync.sync_all()
    schedule_sync()
    {:noreply, state}
  end

  def handle_info({:sync_user, user_id}, state) do
    Web.LichessSync.sync_user(user_id)
    {:noreply, state}
  end

  defp schedule_sync, do: Process.send_after(self(), :sync, @interval_ms)
end
