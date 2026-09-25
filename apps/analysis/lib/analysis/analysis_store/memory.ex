defmodule Analysis.AnalysisStore.Memory do
  @moduledoc false

  use GenServer

  @behaviour Analysis.AnalysisStore

  alias Analysis.Analysis

  @type revision :: pos_integer()
  @type store :: GenServer.server()

  @type entry :: %{
          analysis: Analysis.t(),
          revision: revision()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      %{},
      Keyword.take(opts, [:name])
    )
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  @spec insert(store(), Analysis.t()) ::
          {:ok, revision()}
          | {:error, :already_exists}
  def insert(store, %Analysis{} = analysis) do
    GenServer.call(store, {:insert, analysis})
  end

  @impl true
  @spec get(store(), Analysis.id()) ::
          {:ok, Analysis.t(), revision()}
          | :not_found
  def get(store, analysis_id) do
    GenServer.call(store, {:get, analysis_id})
  end

  @impl true
  @spec list(store()) :: [{Analysis.t(), revision()}]
  def list(store) do
    GenServer.call(store, :list)
  end

  @impl true
  @spec update(store(), Analysis.t(), revision()) ::
          {:ok, revision()}
          | {:error, :not_found | :conflict}
  def update(store, %Analysis{} = analysis, expected_revision) do
    GenServer.call(
      store,
      {:update, analysis, expected_revision}
    )
  end

  @impl true
  @spec delete(store(), Analysis.id(), revision()) ::
          :ok
          | {:error, :not_found | :conflict}
  def delete(store, analysis_id, expected_revision) do
    GenServer.call(
      store,
      {:delete, analysis_id, expected_revision}
    )
  end

  @impl true
  def init(analyses) do
    {:ok, analyses}
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        analyses
      ) do
    {:reply, :ok, analyses}
  end

  @impl true
  def handle_call(
        {:insert, %Analysis{id: id} = analysis},
        _from,
        analyses
      ) do
    if Map.has_key?(analyses, id) do
      {:reply, {:error, :already_exists}, analyses}
    else
      revision = 1
      entry = %{analysis: analysis, revision: revision}

      {:reply, {:ok, revision}, Map.put(analyses, id, entry)}
    end
  end

  def handle_call({:get, analysis_id}, _from, analyses) do
    reply =
      case Map.fetch(analyses, analysis_id) do
        {:ok, %{analysis: analysis, revision: revision}} ->
          {:ok, analysis, revision}

        :error ->
          :not_found
      end

    {:reply, reply, analyses}
  end

  def handle_call(:list, _from, analyses) do
    entries =
      Enum.map(analyses, fn {_id, %{analysis: analysis, revision: revision}} ->
        {analysis, revision}
      end)

    {:reply, entries, analyses}
  end

  def handle_call(
        {:update, %Analysis{id: id} = analysis, expected_revision},
        _from,
        analyses
      ) do
    case Map.fetch(analyses, id) do
      :error ->
        {:reply, {:error, :not_found}, analyses}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, analyses}

      {:ok, %{revision: revision}} ->
        new_revision = revision + 1

        entry = %{
          analysis: analysis,
          revision: new_revision
        }

        {:reply, {:ok, new_revision}, Map.put(analyses, id, entry)}
    end
  end

  def handle_call(
        {:delete, analysis_id, expected_revision},
        _from,
        analyses
      ) do
    case Map.fetch(analyses, analysis_id) do
      :error ->
        {:reply, {:error, :not_found}, analyses}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, analyses}

      {:ok, _entry} ->
        {:reply, :ok, Map.delete(analyses, analysis_id)}
    end
  end
end
