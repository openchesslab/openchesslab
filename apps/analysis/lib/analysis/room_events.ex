defmodule Analysis.RoomEvents do
  @moduledoc false

  @scope __MODULE__

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: @scope,
      start: {:pg, :start_link, [@scope]}
    }
  end

  @spec subscribe(Analysis.Room.id()) :: :ok
  def subscribe(room_id) do
    :ok = :pg.join(@scope, group(room_id), self())
  end

  @spec unsubscribe(Analysis.Room.id()) :: :ok
  def unsubscribe(room_id) do
    :ok = :pg.leave(@scope, group(room_id), self())
  end

  @spec publish_changed(Analysis.Room.id()) :: :ok
  def publish_changed(room_id) do
    @scope
    |> :pg.get_members(group(room_id))
    |> Enum.each(&send(&1, {:room_changed, room_id}))

    :ok
  end

  defp group(room_id), do: {:room, room_id}
end
