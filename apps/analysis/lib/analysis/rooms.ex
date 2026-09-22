defmodule Analysis.Rooms do
  @moduledoc false

  alias Analysis.Room
  alias Analysis.RoomServer

  @registry Analysis.RoomRegistry
  @supervisor Analysis.RoomSupervisor

  @spec start_room(Room.id()) :: {:ok, Room.t()}
  def start_room(room_id) do
    room = Room.new(room_id)

    case Horde.DynamicSupervisor.start_child(
           @supervisor,
           {RoomServer, room}
         ) do
      {:ok, pid} ->
        {:ok, RoomServer.get(pid)}

      {:error, {:already_started, pid}} ->
        {:ok, RoomServer.get(pid)}

      {:error, {:already_registered, pid}} ->
        {:ok, RoomServer.get(pid)}
    end
  end

  @spec get(Room.id()) :: {:ok, Room.t()} | :not_found
  def get(room_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        {:ok, RoomServer.get(pid)}

      :not_found ->
        :not_found
    end
  end

  @spec add_game(Room.id(), Room.game_id()) ::
          :ok | {:error, :not_found}
  def add_game(room_id, game_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        RoomServer.add_game(pid, game_id)

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec remove_game(Room.id(), Room.game_id()) ::
          :ok | {:error, :not_found}
  def remove_game(room_id, game_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        RoomServer.remove_game(pid, game_id)

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec stop_room(Room.id()) :: :ok
  def stop_room(room_id) do
    case lookup(room_id) do
      {:ok, pid} ->
        case Horde.DynamicSupervisor.terminate_child(@supervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end

      :not_found ->
        :ok
    end
  end

  defp lookup(room_id) do
    deadline =
      System.monotonic_time(:millisecond) + 100

    lookup_until(room_id, deadline)
  end

  defp lookup_until(room_id, deadline) do
    case Horde.Registry.lookup(@registry, room_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(1)
          lookup_until(room_id, deadline)
        else
          :not_found
        end
    end
  end
end
