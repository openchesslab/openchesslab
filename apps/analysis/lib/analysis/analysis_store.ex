defmodule Analysis.AnalysisStore do
  @moduledoc false

  alias Analysis.Analysis, as: AnalysisModel

  @default_adapter Analysis.AnalysisStore.Memory

  @registry Analysis.AnalysisStoreRegistry
  @registry_key :analysis_store

  @type store :: GenServer.server()
  @type revision :: pos_integer()

  @callback insert(store(), AnalysisModel.t()) ::
              {:ok, revision()}
              | {:error, :already_exists}

  @callback get(store(), AnalysisModel.id()) ::
              {:ok, AnalysisModel.t(), revision()}
              | :not_found

  @callback list(store()) ::
              [{AnalysisModel.t(), revision()}]

  @callback update(store(), AnalysisModel.t(), revision()) ::
              {:ok, revision()}
              | {:error, :not_found | :conflict}

  @callback delete(store(), AnalysisModel.id(), revision()) ::
              :ok
              | {:error, :not_found | :conflict}

  @spec clustered_store() :: GenServer.server()
  def clustered_store do
    {:via, Horde.Registry, {@registry, @registry_key}}
  end

  @spec ready?() :: boolean()
  def ready? do
    try do
      GenServer.call(
        store(),
        :ping,
        1_000
      ) == :ok
    catch
      :exit, _reason ->
        false
    end
  end

  @spec insert(AnalysisModel.t()) ::
          {:ok, revision()}
          | {:error, :already_exists}
  def insert(%AnalysisModel{} = analysis) do
    adapter().insert(store(), analysis)
  end

  @spec get(AnalysisModel.id()) ::
          {:ok, AnalysisModel.t(), revision()}
          | :not_found
  def get(analysis_id) do
    adapter().get(store(), analysis_id)
  end

  @spec list() :: [{AnalysisModel.t(), revision()}]
  def list do
    adapter().list(store())
  end

  @spec update(AnalysisModel.t(), revision()) ::
          {:ok, revision()}
          | {:error, :not_found | :conflict}
  def update(%AnalysisModel{} = analysis, expected_revision) do
    adapter().update(
      store(),
      analysis,
      expected_revision
    )
  end

  @spec delete(AnalysisModel.id(), revision()) ::
          :ok
          | {:error, :not_found | :conflict}
  def delete(analysis_id, expected_revision) do
    adapter().delete(
      store(),
      analysis_id,
      expected_revision
    )
  end

  defp adapter do
    config()
    |> Keyword.get(
      :adapter,
      @default_adapter
    )
  end

  defp store do
    config()
    |> Keyword.get(
      :store,
      clustered_store()
    )
  end

  defp config do
    Application.get_env(
      :analysis,
      __MODULE__,
      []
    )
  end
end
