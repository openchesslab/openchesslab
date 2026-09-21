defmodule Analysis.GameEvents do
  @moduledoc false

  @scope __MODULE__

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: @scope,
      start: {:pg, :start_link, [@scope]}
    }
  end

  @spec subscribe(Analysis.Game.id()) :: :ok
  def subscribe(game_id) do
    :ok = :pg.join(@scope, group(game_id), self())
  end

  @spec unsubscribe(Analysis.Game.id()) :: :ok
  def unsubscribe(game_id) do
    :ok = :pg.leave(@scope, group(game_id), self())
  end

  @spec publish_changed(Analysis.Game.id()) :: :ok
  def publish_changed(game_id) do
    @scope
    |> :pg.get_members(group(game_id))
    |> Enum.each(&send(&1, {:game_changed, game_id}))

    :ok
  end

  defp group(game_id), do: {:game, game_id}
end
