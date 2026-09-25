defmodule Analysis.AnalysisEventsTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisEvents
  alias Analysis.Analyses
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  setup do
    analysis_id = "analysis-#{System.unique_integer([:positive])}"

    %{analysis_id: analysis_id}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp insert_analysis(analysis_id) do
    position_id =
      Position.starting_position()
      |> PositionStore.append()

    analysis = AnalysisModel.new(analysis_id, position_id)

    {:ok, 1} = Analyses.insert(analysis)

    analysis
  end

  test "publishes an event after an analysis is changed", %{analysis_id: analysis_id} do
    insert_analysis(analysis_id)

    assert :ok = AnalysisEvents.subscribe(analysis_id)

    assert {:ok, _analysis, 2, [0]} =
             Analyses.play(analysis_id, [], move("e2", "e4"))

    assert_receive {:analysis_changed, ^analysis_id}
  end

  test "does not publish an event when the move is illegal", %{
    analysis_id: analysis_id
  } do
    insert_analysis(analysis_id)

    assert :ok = AnalysisEvents.subscribe(analysis_id)

    assert {:error, :illegal_move} =
             Analyses.play(analysis_id, [], move("e2", "e5"))

    refute_receive {:analysis_changed, ^analysis_id}
  end

  test "does not publish an event when the analysis does not exist", %{
    analysis_id: analysis_id
  } do
    assert :ok = AnalysisEvents.subscribe(analysis_id)

    assert {:error, :analysis_not_found} =
             Analyses.play(analysis_id, [], move("e2", "e4"))

    refute_receive {:analysis_changed, ^analysis_id}
  end

  test "events are scoped to the analysis", %{analysis_id: analysis_id} do
    other_analysis_id = "#{analysis_id}-other"

    insert_analysis(analysis_id)
    insert_analysis(other_analysis_id)

    assert :ok = AnalysisEvents.subscribe(analysis_id)

    assert {:ok, _analysis, 2, [0]} =
             Analyses.play(other_analysis_id, [], move("e2", "e4"))

    refute_receive {:analysis_changed, ^analysis_id}
    refute_receive {:analysis_changed, ^other_analysis_id}
  end
end
