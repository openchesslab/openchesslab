defmodule Analysis.Rooms do
  @moduledoc false

  alias Analysis.Room
  alias Analysis.RoomServer

  @default_registry Analysis.RoomRegistry
  @default_supervisor Analysis.RoomSupervisor

  @type option ::
          {:registry, atom()}
          | {:supervisor, atom()}

  @type options :: [option()]

  @spec start_room(
          Room.id(),
          options()
        ) :: {:ok, Room.t()}
  def start_room(
        room_id,
        opts \\ []
      ) do
    registry =
      registry(opts)

    supervisor =
      supervisor(opts)

    room =
      Room.new(room_id)

    case Horde.DynamicSupervisor.start_child(
           supervisor,
           {
             RoomServer,
             {room, registry}
           }
         ) do
      {:ok, pid} ->
        {:ok, RoomServer.get(pid)}

      {:error, {:already_started, pid}} ->
        {:ok, RoomServer.get(pid)}

      {:error, {:already_registered, pid}} ->
        {:ok, RoomServer.get(pid)}
    end
  end

  @spec get(
          Room.id(),
          options()
        ) ::
          {:ok, Room.t()}
          | :not_found
  def get(
        room_id,
        opts \\ []
      ) do
    case lookup(
           registry(opts),
           room_id
         ) do
      {:ok, pid} ->
        {:ok, RoomServer.get(pid)}

      :not_found ->
        :not_found
    end
  end

  @spec add_analysis(
          Room.id(),
          Room.analysis_id(),
          options()
        ) ::
          :ok
          | {:error, :not_found}
  def add_analysis(
        room_id,
        analysis_id,
        opts \\ []
      ) do
    case lookup(
           registry(opts),
           room_id
         ) do
      {:ok, pid} ->
        RoomServer.add_analysis(
          pid,
          analysis_id
        )

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec remove_analysis(
          Room.id(),
          Room.analysis_id(),
          options()
        ) ::
          :ok
          | {:error, :not_found}
  def remove_analysis(
        room_id,
        analysis_id,
        opts \\ []
      ) do
    case lookup(
           registry(opts),
           room_id
         ) do
      {:ok, pid} ->
        RoomServer.remove_analysis(
          pid,
          analysis_id
        )

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec stop_room(
          Room.id(),
          options()
        ) :: :ok
  def stop_room(
        room_id,
        opts \\ []
      ) do
    case lookup(
           registry(opts),
           room_id
         ) do
      {:ok, pid} ->
        case Horde.DynamicSupervisor.terminate_child(
               supervisor(opts),
               pid
             ) do
          :ok ->
            :ok

          {:error, :not_found} ->
            :ok
        end

      :not_found ->
        :ok
    end
  end

  defp lookup(
         registry,
         room_id
       ) do
    case Horde.Registry.lookup(
           registry,
           room_id
         ) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        :not_found
    end
  end

  defp registry(opts) do
    Keyword.get(
      opts,
      :registry,
      @default_registry
    )
  end

  defp supervisor(opts) do
    Keyword.get(
      opts,
      :supervisor,
      @default_supervisor
    )
  end
end
