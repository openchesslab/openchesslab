defmodule Analysis.Rooms do
  @moduledoc false

  alias Analysis.Room
  alias Analysis.RoomChat
  alias Analysis.RoomServer
  alias Analysis.RoomStore

  @default_registry Analysis.RoomRegistry
  @default_supervisor Analysis.RoomSupervisor

  @type option ::
          {:registry, atom()}
          | {:supervisor, atom()}

  @type options :: [option()]

  @doc "Create a new room; unlike `start_room/2`, never reuse an existing code."
  @spec create_room(Room.id(), options()) ::
          {:ok, Room.t()} | {:error, :already_exists | :not_found}
  def create_room(room_id, opts \\ []) do
    case RoomStore.create(room_id) do
      :ok ->
        case lookup(registry(opts), room_id, opts) do
          {:ok, pid} -> {:ok, RoomServer.get(pid)}
          :not_found -> {:error, :not_found}
        end

      {:error, :already_exists} = error ->
        error
    end
  end

  @spec start_room(
          Room.id(),
          options()
        ) :: {:ok, Room.t()}
  def start_room(room_id, opts \\ []) do
    :ok = RoomStore.ensure(room_id)

    case lookup(registry(opts), room_id, opts) do
      {:ok, pid} -> {:ok, RoomServer.get(pid)}
    end
  end

  @spec get(
          Room.id(),
          options()
        ) ::
          {:ok, Room.t()}
          | :not_found
  def get(room_id, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
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
  def add_analysis(room_id, analysis_id, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
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
  def remove_analysis(room_id, analysis_id, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
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

  @spec chat(
          Room.id(),
          options()
        ) ::
          {:ok, [RoomChat.Message.t()]}
          | {:error, :not_found}
  def chat(room_id, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
         ) do
      {:ok, pid} ->
        {:ok, RoomServer.chat(pid)}

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec send_message(
          Room.id(),
          map(),
          options()
        ) ::
          {:ok, RoomChat.Message.t()}
          | {:error, :not_found | :empty}
  def send_message(room_id, attrs, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
         ) do
      {:ok, pid} ->
        RoomServer.send_message(
          pid,
          attrs
        )

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec region(
          Room.id(),
          options()
        ) ::
          {:ok, String.t()}
          | {:error, :not_found}
  def region(room_id, opts \\ []) do
    case lookup(
           registry(opts),
           room_id,
           opts
         ) do
      {:ok, pid} ->
        {:ok, node_region(node(pid))}

      :not_found ->
        {:error, :not_found}
    end
  end

  @spec stop_room(
          Room.id(),
          options()
        ) :: :ok
  def stop_room(room_id, opts \\ []) do
    :ok = RoomStore.delete(room_id)

    case lookup_process(registry(opts), room_id) do
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

  # Recreate a worker on demand after a machine restart; never create a
  # previously unknown room from a read path.
  defp lookup(registry, room_id, opts) do
    case lookup_process(registry, room_id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        case RoomStore.get(room_id) do
          {:ok, room} -> start_worker(room, registry, supervisor(opts))
          :not_found -> :not_found
        end
    end
  end

  defp start_worker(room, registry, supervisor) do
    case Horde.DynamicSupervisor.start_child(
           supervisor,
           {RoomServer, {room, registry, :durable}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_registered, pid}} -> {:ok, pid}
    end
  end

  defp lookup_process(registry, room_id) do
    case Horde.Registry.lookup(registry, room_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  defp node_region(node_name) do
    case :erpc.call(
           node_name,
           System,
           :get_env,
           ["FLY_REGION"],
           2000
         ) do
      region when is_binary(region) ->
        region

      _ ->
        "local"
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
