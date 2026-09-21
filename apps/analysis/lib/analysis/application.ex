defmodule Analysis.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Analysis.RoomEvents,
      {Horde.Registry, name: Analysis.RoomRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: Analysis.RoomSupervisor, strategy: :one_for_one, members: :auto}
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: Analysis.Supervisor
    )
  end
end
