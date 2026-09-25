defmodule Analysis.AnalysisStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore

  defmodule RecordingAdapter do
    @behaviour Analysis.AnalysisStore

    def insert(store, analysis) do
      send(self(), {:insert, store, analysis})
      {:ok, 1}
    end

    def get(store, analysis_id) do
      send(self(), {:get, store, analysis_id})
      :not_found
    end

    def list(store) do
      send(self(), {:list, store})
      []
    end

    def update(store, analysis, revision) do
      send(self(), {:update, store, analysis, revision})
      {:ok, revision + 1}
    end

    def delete(store, analysis_id, revision) do
      send(self(), {:delete, store, analysis_id, revision})
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

  test "uses the cluster-wide store by default" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      adapter: RecordingAdapter
    )

    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    assert_received {
      :insert,
      store,
      ^analysis
    }

    assert store == AnalysisStore.clustered_store()
  end

  test "reports ready when the analysis store is reachable" do
    Application.delete_env(
      :analysis,
      AnalysisStore
    )

    assert AnalysisStore.ready?()
  end

  test "reports not ready when the configured analysis store is unavailable" do
    Application.put_env(
      :analysis,
      AnalysisStore,
      store: :unavailable_analysis_store
    )

    refute AnalysisStore.ready?()
  end
end
