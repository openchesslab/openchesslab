defmodule Analysis.AnalysisEvents do
  @moduledoc false

  @scope __MODULE__

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: @scope,
      start: {:pg, :start_link, [@scope]}
    }
  end

  @spec subscribe(Analysis.Analysis.id()) :: :ok
  def subscribe(analysis_id) do
    :ok = :pg.join(@scope, group(analysis_id), self())
  end

  @spec unsubscribe(Analysis.Analysis.id()) :: :ok
  def unsubscribe(analysis_id) do
    :ok = :pg.leave(@scope, group(analysis_id), self())
  end

  @spec publish_changed(Analysis.Analysis.id()) :: :ok
  def publish_changed(analysis_id) do
    @scope
    |> :pg.get_members(group(analysis_id))
    |> Enum.each(&send(&1, {:analysis_changed, analysis_id}))

    :ok
  end

  defp group(analysis_id), do: {:analysis, analysis_id}
end
