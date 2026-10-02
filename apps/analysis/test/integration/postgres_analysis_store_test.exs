defmodule Analysis.PostgresAnalysisStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE analyses
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "stores and loads an analysis aggregate with revision 1" do
    analysis =
      "analysis-1"
      |> AnalysisModel.new(
        42,
        %{
          event: "Candidates"
        }
      )
      |> AnalysisModel.add_child(
        [],
        Transition.move(
          Move.new(
            12,
            28
          )
        ),
        43
      )

    {:ok, analysis} =
      AnalysisModel.set_comment(
        analysis,
        [0],
        "Main line"
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    assert AnalysisStore.get("analysis-1") ==
             {
               :ok,
               analysis,
               1
             }

    assert [
             [
               "analysis-1",
               1,
               record
             ]
           ] =
             Repo.query!(
               """
               SELECT
                 analysis_id,
                 revision,
                 record
               FROM analyses
               """,
               []
             ).rows

    assert <<
             "OCLANL01",
             _payload::binary
           >> = record
  end

  test "does not overwrite an existing analysis" do
    first =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    second =
      AnalysisModel.new(
        "analysis-1",
        43
      )

    assert {:ok, 1} =
             AnalysisStore.insert(first)

    assert AnalysisStore.insert(second) ==
             {:error, :already_exists}

    assert AnalysisStore.get("analysis-1") ==
             {
               :ok,
               first,
               1
             }

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM analyses
               """,
               []
             ).rows
  end

  test "updates an analysis when the expected revision matches" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    updated_analysis =
      %{
        analysis
        | metadata: %{
            event: "Candidates"
          }
      }

    assert {:ok, 2} =
             AnalysisStore.update(
               updated_analysis,
               1
             )

    assert AnalysisStore.get("analysis-1") ==
             {
               :ok,
               updated_analysis,
               2
             }

    assert [[2]] =
             Repo.query!(
               """
               SELECT revision
               FROM analyses
               WHERE analysis_id = 'analysis-1'
               """,
               []
             ).rows
  end

  test "rejects an update with a stale revision" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    first_update =
      %{
        analysis
        | metadata: %{
            version: 1
          }
      }

    assert {:ok, 2} =
             AnalysisStore.update(
               first_update,
               1
             )

    stale_update =
      %{
        analysis
        | metadata: %{
            version: 2
          }
      }

    assert AnalysisStore.update(
             stale_update,
             1
           ) ==
             {:error, :conflict}

    assert AnalysisStore.get("analysis-1") ==
             {
               :ok,
               first_update,
               2
             }
  end

  test "returns not found when updating an unknown analysis" do
    analysis =
      AnalysisModel.new(
        "missing",
        42
      )

    assert AnalysisStore.update(
             analysis,
             1
           ) ==
             {:error, :not_found}
  end

  test "allows only one concurrent update for one expected revision" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    first_update =
      %{
        analysis
        | metadata: %{
            version: 1
          }
      }

    second_update =
      %{
        analysis
        | metadata: %{
            version: 2
          }
      }

    results =
      [
        first_update,
        second_update
      ]
      |> Enum.map(fn updated_analysis ->
        Task.async(fn ->
          AnalysisStore.update(
            updated_analysis,
            1
          )
        end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(
             results,
             &(&1 == {:ok, 2})
           ) ==
             1

    assert Enum.count(
             results,
             &(&1 == {:error, :conflict})
           ) ==
             1

    assert {
             :ok,
             stored_analysis,
             2
           } =
             AnalysisStore.get("analysis-1")

    assert stored_analysis.metadata in [
             %{version: 1},
             %{version: 2}
           ]
  end

  test "deletes an analysis when the expected revision matches" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    assert :ok =
             AnalysisStore.delete(
               "analysis-1",
               1
             )

    assert AnalysisStore.get("analysis-1") ==
             :not_found
  end

  test "rejects deletion with a stale revision" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    updated_analysis =
      %{
        analysis
        | metadata: %{
            version: 2
          }
      }

    assert {:ok, 2} =
             AnalysisStore.update(
               updated_analysis,
               1
             )

    assert AnalysisStore.delete(
             "analysis-1",
             1
           ) ==
             {:error, :conflict}

    assert AnalysisStore.get("analysis-1") ==
             {
               :ok,
               updated_analysis,
               2
             }
  end

  test "returns not found when deleting an unknown analysis" do
    assert AnalysisStore.delete(
             "missing",
             1
           ) ==
             {:error, :not_found}
  end

  test "lists stored analyses with their current revisions" do
    first =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    second =
      AnalysisModel.new(
        "analysis-2",
        43
      )

    assert {:ok, 1} =
             AnalysisStore.insert(first)

    assert {:ok, 1} =
             AnalysisStore.insert(second)

    updated_second =
      %{
        second
        | metadata: %{
            event: "Candidates"
          }
      }

    assert {:ok, 2} =
             AnalysisStore.update(
               updated_second,
               1
             )

    assert AnalysisStore.list() == [
             {
               first,
               1
             },
             {
               updated_second,
               2
             }
           ]
  end

  test "returns not found for an unknown analysis id" do
    assert AnalysisStore.get("missing") ==
             :not_found
  end

  test "persists node comments and nags through the durable codec" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    {:ok, analysis} =
      AnalysisModel.set_comment(
        analysis,
        [],
        "Critical position"
      )

    {:ok, analysis} =
      AnalysisModel.set_nags(
        analysis,
        [],
        [1, 5]
      )

    assert {:ok, 1} =
             AnalysisStore.insert(analysis)

    assert {
             :ok,
             stored_analysis,
             1
           } =
             AnalysisStore.get("analysis-1")

    root =
      AnalysisModel.root(stored_analysis)

    assert Node.comment(root) ==
             "Critical position"

    assert Node.nags(root) ==
             [1, 5]
  end
end
