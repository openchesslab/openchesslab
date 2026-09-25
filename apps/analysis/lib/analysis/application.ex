defmodule Analysis.Application do
  @moduledoc false

  use Application

  alias Analysis.PositionStore
  alias Analysis.PositionStoreOwner

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
    position_store_options =
      Application.get_env(
        :analysis,
        PositionStore,
        []
      )

    [
      dns_cluster_child(),
      Analysis.RoomEvents,
      Analysis.GameEvents,
      {
        Horde.Registry,
        name: Analysis.PositionStoreRegistry, keys: :unique, members: :auto
      }
    ] ++
      position_store_children(position_store_options) ++
      [
        {
          Analysis.GameStore.Memory,
          name: Analysis.GameStore.Runtime
        },
        {
          Horde.Registry,
          name: Analysis.RoomRegistry, keys: :unique, members: :auto
        },
        {
          Horde.DynamicSupervisor,
          name: Analysis.RoomSupervisor, strategy: :one_for_one, members: :auto
        }
      ]
  end

  defp position_store_children(options) do
    if PositionStoreOwner.owner?() do
      [
        {
          PositionStore,
          Keyword.put_new(
            options,
            :server,
            PositionStore.clustered_server()
          )
        }
      ]
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
