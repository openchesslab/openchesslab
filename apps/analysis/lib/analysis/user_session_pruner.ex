defmodule Analysis.UserSessionPruner do
  @moduledoc "Hourly production cleanup of at most 1,000 expired user sessions per pass."

  use GenServer

  alias Analysis.UserSessions

  require Logger

  @initial_delay_ms to_timeout(minute: 1)
  @interval_ms to_timeout(hour: 1)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       interval_ms: Keyword.get(opts, :interval_ms, @interval_ms),
       timer: schedule(Keyword.get(opts, :initial_delay_ms, @initial_delay_ms))
     }}
  end

  @impl true
  def handle_info(:prune, state) do
    Process.cancel_timer(state.timer)

    try do
      deleted = UserSessions.prune_expired()
      if deleted > 0, do: Logger.info("Pruned #{deleted} expired user sessions")
    rescue
      _exception -> Logger.error("User session pruning failed")
    catch
      :exit, _reason -> Logger.error("User session pruning failed")
    end

    {:noreply, %{state | timer: schedule(state.interval_ms)}}
  end

  defp schedule(delay_ms), do: Process.send_after(self(), :prune, delay_ms)
end
