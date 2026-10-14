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
          | {:owner, Room.owner_user_id()}

  @type options :: [option()]

  @doc """
  Create a new room; unlike `start_room/2`, never reuse an existing code.

  With `owner:` the room is private: the room code alone never grants entry,
  and the owner becomes its first member. The caller authenticates the owner
  user first; this is not an authorization boundary.
  """
  @spec create_room(Room.id(), options()) ::
          {:ok, Room.t()} | {:error, :already_exists | :not_found | :invalid_owner}
  def create_room(room_id, opts \\ []) do
    created =
      case Keyword.get(opts, :owner) do
        nil -> RoomStore.create(room_id)
        owner_user_id -> RoomStore.create_private(room_id, owner_user_id)
      end

    case created do
      :ok ->
        case lookup(registry(opts), room_id, opts) do
          {:ok, pid} -> {:ok, RoomServer.get(pid)}
          :not_found -> {:error, :not_found}
        end

      {:error, :already_exists} = error ->
        error

      {:error, :invalid_owner} = error ->
        error
    end
  end

  @doc "Membership check for private-room gating; owners are members at creation."
  @spec member?(Room.id(), String.t() | nil) :: boolean()
  def member?(room_id, user_id) do
    RoomStore.member?(room_id, user_id)
  end

  @doc "Admit a user through a raw invite token; returns the token only once elsewhere."
  @spec consume_invite(Room.id(), String.t(), String.t()) ::
          {:ok, :joined} | {:error, :invalid_invite}
  def consume_invite(room_id, user_id, token) when is_binary(token) do
    RoomStore.consume_invite(room_id, user_id, :crypto.hash(:sha256, token))
  end

  def consume_invite(_, _, _), do: {:error, :invalid_invite}

  @doc """
  Generate a fresh multi-use invite link for the room, rotating any older one.

  Only the owner may call this (checked by the caller against the room's
  owner); the raw token is returned once and only its SHA-256 hash is stored.
  """
  @spec create_invite(Room.id()) :: {:ok, String.t()}
  def create_invite(room_id) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    :ok = RoomStore.create_invite(room_id, :crypto.hash(:sha256, token))
    {:ok, token}
  end

  @doc "Revoke every active invite link; the owner-only cutoff is checked by the caller."
  @spec revoke_invites(Room.id()) :: non_neg_integer()
  def revoke_invites(room_id) do
    RoomStore.revoke_invites(room_id)
  end

  @doc "Does the room have an active (non-revoked) invite link?"
  @spec invite_active?(Room.id()) :: boolean()
  def invite_active?(room_id) do
    RoomStore.invite_active?(room_id)
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

  @doc "Prunes old empty rooms in a bounded batch and stops their workers."
  @spec prune_old_empty_rooms(non_neg_integer(), pos_integer(), options()) :: [Room.id()]
  def prune_old_empty_rooms(older_than_days \\ 30, limit \\ 100, opts \\ []) do
    deleted_ids = RoomStore.prune_old_empty_rooms(older_than_days, limit)
    Enum.each(deleted_ids, &terminate_room_worker(&1, opts))
    deleted_ids
  end

  @spec stop_room(
          Room.id(),
          options()
        ) :: :ok
  def stop_room(room_id, opts \\ []) do
    :ok = RoomStore.delete(room_id)
    terminate_room_worker(room_id, opts)
  end

  defp terminate_room_worker(room_id, opts) do
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
