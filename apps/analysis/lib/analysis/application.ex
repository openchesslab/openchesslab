defmodule Analysis.Application do
  @moduledoc false

  use Application

  alias Analysis.GameStore
  alias Analysis.GameStoreOwner
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

    game_store_options =
      Application.get_env(
        :analysis,
        GameStore,
        []
      )

    [
      dns_cluster_child(),
      Analysis.RoomEvents,
      Analysis.GameEvents,
      {
        Horde.Registry,
        name: Analysis.PositionStoreRegistry, keys: :unique, members: :auto
      },
      {
        Horde.Registry,
        name: Analysis.GameStoreRegistry, keys: :unique, members: :auto
      }
    ] ++
      position_store_children(position_store_options) ++
      game_store_children(game_store_options) ++
      [
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

  defp game_store_children(options) do
    if GameStoreOwner.owner?() do
      adapter =
        Keyword.get(
          options,
          :adapter,
          Analysis.GameStore.Memory
        )

      store =
        Keyword.get(
          options,
          :store,
          GameStore.clustered_store()
        )

      adapter_options =
        options
        |> Keyword.delete(:adapter)
        |> Keyword.delete(:store)
        |> Keyword.put_new(:name, store)

      [
        {
          adapter,
          adapter_options
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
