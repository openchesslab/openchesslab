defmodule Analysis.AnalysisStore.Dets do
  @moduledoc false

  use GenServer

  @behaviour Analysis.AnalysisStore

  alias Analysis.Analysis

  @table __MODULE__

  @type revision :: pos_integer()
  @type store :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    path = Keyword.fetch!(opts, :path)

    GenServer.start_link(
      __MODULE__,
      path,
      Keyword.take(opts, [:name])
    )
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
  def init(path) do
    options = [
      file: String.to_charlist(path),
      type: :set,
      keypos: 1
    ]

    case :dets.open_file(@table, options) do
      {:ok, @table} ->
        {:ok, @table}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        table
      ) do
    {:reply, :ok, table}
  end

  @impl true
  def handle_call(
        {:insert, %Analysis{id: id} = analysis},
        _from,
        table
      ) do
    case :dets.insert_new(table, {id, 1, analysis}) do
      true ->
        :ok = :dets.sync(table)
        {:reply, {:ok, 1}, table}

      false ->
        {:reply, {:error, :already_exists}, table}
    end
  end

  def handle_call({:get, analysis_id}, _from, table) do
    reply =
      case :dets.lookup(table, analysis_id) do
        [{^analysis_id, revision, analysis}] ->
          {:ok, analysis, revision}

        [] ->
          :not_found
      end

    {:reply, reply, table}
  end

  def handle_call(:list, _from, table) do
    analyses =
      :dets.foldl(
        fn {_id, revision, analysis}, acc ->
          [{analysis, revision} | acc]
        end,
        [],
        table
      )

    {:reply, analyses, table}
  end

  def handle_call(
        {:update, %Analysis{id: id} = analysis, expected_revision},
        _from,
        table
      ) do
    case :dets.lookup(table, id) do
      [] ->
        {:reply, {:error, :not_found}, table}

      [{^id, revision, _stored_analysis}]
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, table}

      [{^id, revision, _stored_analysis}] ->
        new_revision = revision + 1

        :ok =
          :dets.insert(
            table,
            {id, new_revision, analysis}
          )

        :ok = :dets.sync(table)

        {:reply, {:ok, new_revision}, table}
    end
  end

  def handle_call(
        {:delete, analysis_id, expected_revision},
        _from,
        table
      ) do
    case :dets.lookup(table, analysis_id) do
      [] ->
        {:reply, {:error, :not_found}, table}

      [{^analysis_id, revision, _analysis}]
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, table}

      [{^analysis_id, _revision, _analysis}] ->
        :ok = :dets.delete(table, analysis_id)
        :ok = :dets.sync(table)

        {:reply, :ok, table}
    end
  end

  @impl true
  def terminate(_reason, table) do
    :dets.close(table)
    :ok
  end
end
