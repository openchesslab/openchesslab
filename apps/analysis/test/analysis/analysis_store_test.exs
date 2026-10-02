defmodule Analysis.AnalysisStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore

  defmodule RecordingAdapter do
    @moduledoc false

    @behaviour AnalysisStore

    def insert(store, analysis) do
      send(
        self(),
        {
          :legacy_insert,
          store,
          analysis
        }
      )

      {:ok, 99}
    end

    def get(store, analysis_id) do
      send(
        self(),
        {
          :legacy_get,
          store,
          analysis_id
        }
      )

      :not_found
    end

    def list(store) do
      send(
        self(),
        {
          :legacy_list,
          store
        }
      )

      []
    end

    def update(store, analysis, revision) do
      send(
        self(),
        {
          :legacy_update,
          store,
          analysis,
          revision
        }
      )

      {:ok, revision + 1}
    end

    def delete(store, analysis_id, revision) do
      send(
        self(),
        {
          :legacy_delete,
          store,
          analysis_id,
          revision
        }
      )

      :ok
    end
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        AnalysisStore,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            AnalysisStore
          )

        value ->
          Application.put_env(
            :analysis,
            AnalysisStore,
            value
          )
      end
    end)

    :ok
  end

  test "persists directly through PostgreSQL instead of the configured legacy adapter" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      adapter: RecordingAdapter,
      store: :configured_legacy_store
    )

    analysis_id =
      "analysis-#{System.unique_integer([:positive])}"

    analysis =
      AnalysisModel.new(
        analysis_id,
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    assert AnalysisStore.get(analysis_id) ==
             {
               :ok,
               analysis,
               1
             }

    refute_received {
      :legacy_insert,
      _store,
      _analysis
    }

    refute_received {
      :legacy_get,
      _store,
      _analysis_id
    }
  end

  test "reports ready when the legacy analysis store process is reachable" do
    Application.delete_env(
      :analysis,
      AnalysisStore
    )

    assert AnalysisStore.ready?()
  end

  test "reports not ready when the configured legacy analysis store is unavailable" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      store: :unavailable_analysis_store
    )

    refute AnalysisStore.ready?()
  end

  test "reports not ready when the legacy Horde registry is unavailable" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      store: {
        :via,
        Horde.Registry,
        {
          :unavailable_analysis_store_registry,
          :analysis_store
        }
      }
    )

    refute AnalysisStore.ready?()
  end
end
