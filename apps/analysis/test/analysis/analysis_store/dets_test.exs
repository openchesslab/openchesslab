defmodule Analysis.AnalysisStore.DetsTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore.Dets

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-analysis-store-#{System.unique_integer([:positive])}.dets"
      )

    on_exit(fn ->
      File.rm(path)
    end)

    %{path: path}
  end

  test "inserts and retrieves an analysis", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)
    analysis = AnalysisModel.new("analysis-1", :p0)

    assert {:ok, 1} = Dets.insert(store, analysis)
    assert {:ok, ^analysis, 1} = Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "does not overwrite an existing analysis", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("analysis-1", :p0)
    other = AnalysisModel.new("analysis-1", :other)

    assert {:ok, 1} = Dets.insert(store, analysis)
    assert {:error, :already_exists} = Dets.insert(store, other)

    assert {:ok, ^analysis, 1} = Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "returns not_found for an unknown analysis", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    assert :not_found = Dets.get(store, "missing")

    GenServer.stop(store)
  end

  test "updates an analysis when the revision matches", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("analysis-1", :p0)
    {:ok, revision} = Dets.insert(store, analysis)

    updated_analysis = %{analysis | metadata: %{event: "Candidates"}}

    assert {:ok, 2} =
             Dets.update(store, updated_analysis, revision)

    assert {:ok, ^updated_analysis, 2} =
             Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "rejects an update with a stale revision", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("analysis-1", :p0)
    {:ok, revision} = Dets.insert(store, analysis)

    first_update = %{analysis | metadata: %{version: 1}}

    assert {:ok, new_revision} =
             Dets.update(store, first_update, revision)

    stale_update = %{analysis | metadata: %{version: 2}}

    assert {:error, :conflict} =
             Dets.update(store, stale_update, revision)

    assert {:ok, ^first_update, ^new_revision} =
             Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "returns not_found when updating an unknown analysis", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("missing", :p0)

    assert {:error, :not_found} =
             Dets.update(store, analysis, 1)

    GenServer.stop(store)
  end

  test "deletes an analysis when the revision matches", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("analysis-1", :p0)
    {:ok, revision} = Dets.insert(store, analysis)

    assert :ok = Dets.delete(store, "analysis-1", revision)
    assert :not_found = Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "rejects deletion with a stale revision", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis = AnalysisModel.new("analysis-1", :p0)
    {:ok, revision} = Dets.insert(store, analysis)

    updated_analysis = %{analysis | metadata: %{version: 2}}

    {:ok, new_revision} =
      Dets.update(store, updated_analysis, revision)

    assert {:error, :conflict} =
             Dets.delete(store, "analysis-1", revision)

    assert {:ok, ^updated_analysis, ^new_revision} =
             Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  test "returns not_found when deleting an unknown analysis", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    assert {:error, :not_found} =
             Dets.delete(store, "missing", 1)

    GenServer.stop(store)
  end

  test "persists an analysis and revision across store restarts", %{path: path} do
    {:ok, store} = Dets.start_link(path: path)

    analysis =
      AnalysisModel.new(
        "analysis-1",
        :p0,
        %{event: "World Championship"}
      )

    {:ok, analysis} =
      AnalysisModel.set_comment(analysis, [], "Persistent analysis")

    assert {:ok, 1} = Dets.insert(store, analysis)

    updated_analysis =
      %{analysis | metadata: Map.put(analysis.metadata, :round, "1")}

    assert {:ok, 2} =
             Dets.update(store, updated_analysis, 1)

    GenServer.stop(store)

    {:ok, store} = Dets.start_link(path: path)

    assert {:ok, ^updated_analysis, 2} =
             Dets.get(store, "analysis-1")

    continued_analysis =
      %{updated_analysis | metadata: Map.put(updated_analysis.metadata, :site, "London")}

    assert {:ok, 3} =
             Dets.update(store, continued_analysis, 2)

    assert {:ok, ^continued_analysis, 3} =
             Dets.get(store, "analysis-1")

    GenServer.stop(store)
  end

  describe "list/1" do
    test "returns all stored analyses with their revisions", %{path: path} do
      {:ok, store} = Dets.start_link(path: path)

      analysis_1 = AnalysisModel.new("analysis-1", :p0)
      analysis_2 = AnalysisModel.new("analysis-2", :p1)

      assert {:ok, 1} = Dets.insert(store, analysis_1)
      assert {:ok, 1} = Dets.insert(store, analysis_2)

      assert MapSet.new(Dets.list(store)) ==
               MapSet.new([
                 {analysis_1, 1},
                 {analysis_2, 1}
               ])

      GenServer.stop(store)
    end

    test "returns the current revision", %{path: path} do
      {:ok, store} = Dets.start_link(path: path)

      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, 1} = Dets.insert(store, analysis)

      updated_analysis =
        %{analysis | metadata: %{event: "Candidates"}}

      assert {:ok, 2} =
               Dets.update(store, updated_analysis, 1)

      assert Dets.list(store) == [
               {updated_analysis, 2}
             ]

      GenServer.stop(store)
    end

    test "returns an empty list for an empty store", %{path: path} do
      {:ok, store} = Dets.start_link(path: path)

      assert Dets.list(store) == []

      GenServer.stop(store)
    end
  end
end
