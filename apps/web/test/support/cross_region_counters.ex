defmodule Web.CrossRegionCounters do
  @moduledoc """
  Counts store calls made through the counting proxies.

  Room and analysis processes can live in another Fly region than the
  LiveView that renders them, so every `AnalysisStore`/`PositionStore`
  call is a cross-region round trip (measured ~230 ms in production).
  The proxies in this file forward to the real clustered stores and
  count, so tests can assert that a LiveView flow makes no redundant
  cross-region calls.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
  end

  def bump(key) do
    Agent.update(__MODULE__, &Map.update(&1, key, 1, fn count -> count + 1 end))
  end

  def counts, do: Agent.get(__MODULE__, & &1)

  def reset, do: Agent.update(__MODULE__, fn _ -> %{} end)
end

defmodule Web.CountingPositionStore do
  @moduledoc false

  # Forwards `PositionStore` calls to the real clustered server and counts
  # them. Install per test with:
  #
  #     Application.put_env(:analysis, Analysis.PositionStore, server: Web.CountingPositionStore)

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, Analysis.PositionStore.clustered_server(), name: __MODULE__)
  end

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
  end

  @impl true
  def init(real) do
    {:ok, real}
  end

  @impl true
  def handle_call({:get, _position_id} = call, _from, real) do
    Web.CrossRegionCounters.bump("position:get")
    {:reply, GenServer.call(real, call), real}
  end

  @impl true
  def handle_call({:append, _position} = call, _from, real) do
    Web.CrossRegionCounters.bump("position:append")
    {:reply, GenServer.call(real, call), real}
  end

  @impl true
  def handle_call(call, _from, real) do
    {:reply, GenServer.call(real, call), real}
  end
end

defmodule Web.CountingAnalysisStore do
  @moduledoc false

  # `AnalysisStore` adapter that forwards to the in-memory store and counts
  # the calls. Install per test with:
  #
  #     Application.put_env(:analysis, Analysis.AnalysisStore, adapter: Web.CountingAnalysisStore)

  @behaviour Analysis.AnalysisStore

  @real Analysis.AnalysisStore.Memory

  @impl true
  def insert(store, analysis) do
    Web.CrossRegionCounters.bump("analysis:insert")
    @real.insert(store, analysis)
  end

  @impl true
  def get(store, analysis_id) do
    Web.CrossRegionCounters.bump("analysis:get")
    @real.get(store, analysis_id)
  end

  @impl true
  def list(store) do
    Web.CrossRegionCounters.bump("analysis:list")
    @real.list(store)
  end

  @impl true
  def update(store, analysis, expected_revision) do
    Web.CrossRegionCounters.bump("analysis:update")
    @real.update(store, analysis, expected_revision)
  end

  @impl true
  def delete(store, analysis_id, expected_revision) do
    Web.CrossRegionCounters.bump("analysis:delete")
    @real.delete(store, analysis_id, expected_revision)
  end
end
