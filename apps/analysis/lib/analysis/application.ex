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
    position_store_options =
      Application.get_env(
        :analysis,
        Analysis.PositionStore,
        []
      )

    [
      Analysis.RoomEvents,
      Analysis.GameEvents,
      {
        Horde.Registry,
        name: Analysis.PositionStoreRegistry, keys: :unique, members: :auto
      },
      {
        Analysis.PositionStore,
        position_store_options
      },
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
end
