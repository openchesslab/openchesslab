defmodule Analysis.AnalysisStore.MemoryTest do
  use ExUnit.Case, async: true

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore.Memory

  setup do
    {:ok, store} = Memory.start_link()

    %{store: store}
  end

  describe "insert/2" do
    test "stores an analysis with revision 1", %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, 1} = Memory.insert(store, analysis)
      assert {:ok, ^analysis, 1} = Memory.get(store, "analysis-1")
    end

    test "does not overwrite an existing analysis", %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)
      other = AnalysisModel.new("analysis-1", :other)

      assert {:ok, 1} = Memory.insert(store, analysis)
      assert {:error, :already_exists} = Memory.insert(store, other)

      assert {:ok, ^analysis, 1} = Memory.get(store, "analysis-1")
    end
  end

  describe "get/2" do
    test "returns :not_found for an unknown analysis", %{store: store} do
      assert :not_found = Memory.get(store, "missing")
    end
  end

  describe "list/1" do
    test "returns all stored analyses with their revisions", %{store: store} do
      analysis_1 = AnalysisModel.new("analysis-1", :p0)
      analysis_2 = AnalysisModel.new("analysis-2", :p1)

      assert {:ok, 1} = Memory.insert(store, analysis_1)
      assert {:ok, 1} = Memory.insert(store, analysis_2)

      assert MapSet.new(Memory.list(store)) ==
               MapSet.new([
                 {analysis_1, 1},
                 {analysis_2, 1}
               ])
    end

    test "returns the current revision", %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, 1} = Memory.insert(store, analysis)

      updated_analysis =
        %{analysis | metadata: %{event: "Candidates"}}

      assert {:ok, 2} =
               Memory.update(store, updated_analysis, 1)

      assert Memory.list(store) == [
               {updated_analysis, 2}
             ]
    end

    test "returns an empty list for an empty store", %{store: store} do
      assert Memory.list(store) == []
    end
  end

  describe "update/3" do
    test "replaces an analysis when the expected revision matches",
         %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      {:ok, revision} = Memory.insert(store, analysis)

      updated_analysis = %{analysis | metadata: %{event: "Candidates"}}

      assert {:ok, 2} =
               Memory.update(store, updated_analysis, revision)

      assert {:ok, ^updated_analysis, 2} =
               Memory.get(store, "analysis-1")
    end

    test "rejects an update with a stale revision",
         %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      {:ok, revision} = Memory.insert(store, analysis)

      first_update = %{analysis | metadata: %{version: 1}}

      {:ok, new_revision} =
        Memory.update(store, first_update, revision)

      stale_update = %{analysis | metadata: %{version: 2}}

      assert {:error, :conflict} =
               Memory.update(store, stale_update, revision)

      assert {:ok, ^first_update, ^new_revision} =
               Memory.get(store, "analysis-1")
    end

    test "returns not_found for an unknown analysis",
         %{store: store} do
      analysis = AnalysisModel.new("missing", :p0)

      assert {:error, :not_found} =
               Memory.update(store, analysis, 1)
    end
  end

  describe "delete/3" do
    test "deletes an analysis when the expected revision matches",
         %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      {:ok, revision} = Memory.insert(store, analysis)

      assert :ok =
               Memory.delete(store, "analysis-1", revision)

      assert :not_found = Memory.get(store, "analysis-1")
    end

    test "rejects deletion with a stale revision",
         %{store: store} do
      analysis = AnalysisModel.new("analysis-1", :p0)

      {:ok, revision} = Memory.insert(store, analysis)

      updated_analysis = %{analysis | metadata: %{version: 2}}

      {:ok, new_revision} =
        Memory.update(store, updated_analysis, revision)

      assert {:error, :conflict} =
               Memory.delete(store, "analysis-1", revision)

      assert {:ok, ^updated_analysis, ^new_revision} =
               Memory.get(store, "analysis-1")
    end

    test "returns not_found for an unknown analysis",
         %{store: store} do
      assert {:error, :not_found} =
               Memory.delete(store, "missing", 1)
    end
  end
end
