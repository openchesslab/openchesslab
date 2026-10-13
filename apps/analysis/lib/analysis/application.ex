defmodule Analysis.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      children(),
      strategy: :one_for_one,
      name: Analysis.Supervisor
    )
  end

  @doc false
  def children do
    [
      dns_cluster_child(),
      Analysis.RoomEvents,
      Analysis.AnalysisEvents,
      {
        Horde.Registry,
        name: Analysis.RoomRegistry, keys: :unique, members: :auto
      },
      {
        Horde.DynamicSupervisor,
        name: Analysis.RoomSupervisor, strategy: :one_for_one, members: :auto
      }
    ] ++ room_pruner_children() ++ user_session_pruner_children()
  end

  defp user_session_pruner_children do
    if Application.get_env(:analysis, :user_session_pruning_enabled, false) do
      [Analysis.UserSessionPruner]
    else
      []
    end
  end

  defp room_pruner_children do
    if Application.get_env(:analysis, :room_pruning_enabled, false) do
      [Analysis.RoomPruner]
    else
      []
    end
  end

  defp dns_cluster_child do
    query =
      Application.get_env(
        :analysis,
        :dns_cluster_query,
        :ignore
      )

    {
      DNSCluster,
      query: query
    }
  end
end
