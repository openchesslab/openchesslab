defmodule Analysis.Rooms do
  @moduledoc false

  alias Analysis.Room
  alias Analysis.RoomChat
  alias Analysis.RoomEvents
  alias Analysis.RoomServer
  alias Analysis.RoomStore
  alias Analysis.UserLibrary

  @default_registry Analysis.RoomRegistry
  @default_supervisor Analysis.RoomSupervisor

  @type option ::
          {:registry, atom()}
          | {:supervisor, atom()}
          | {:owner, Room.owner_user_id()}
          | {:owner_display_name, String.t()}

  @type options :: [option()]

  @doc """
  Create a new room; unlike `start_room/2`, never reuse an existing code.

  With `owner:` the room is private: the room code alone never grants entry,
  and the owner becomes its first member. The caller authenticates the owner
  user first; this is not an authorization boundary. `owner_display_name` is
  required for a private room: a server-generated, non-PII label shown in the
  member list.
  """
  @spec create_room(Room.id(), options()) ::
          {:ok, Room.t()} | {:error, :already_exists | :not_found | :invalid_owner}
  def create_room(room_id, opts \\ []) do
    created =
      case Keyword.get(opts, :owner) do
        nil ->
          RoomStore.create(room_id)

        owner_user_id ->
          RoomStore.create_private(
            room_id,
            owner_user_id,
            Keyword.fetch!(opts, :owner_display_name)
          )
      end

    case created do
      :ok ->
        :telemetry.execute([:openchesslab, :room, :created], %{count: 1})

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

  @doc """
  The durable member list, oldest join first. Display names are server
  generated labels without personal data.
  """
  @spec members(Room.id()) :: [
          %{user_id: String.t(), display_name: String.t(), joined_at: NaiveDateTime.t()}
        ]
  def members(room_id), do: RoomStore.members(room_id)

  @doc """
  Remove one member of a private room; only the owner may remove, and the
  owner's own membership is immutable (ownership itself is never transferable
  here). Every connected member view is notified, so a removed member's
  session is cut off immediately. The caller authenticates the owner first.
  """
  @spec remove_member(Room.id(), String.t(), String.t()) ::
          :ok | {:error, :not_owner | :member_not_found | :owner_immutable}
  def remove_member(room_id, owner_user_id, target_user_id)
      when is_binary(room_id) and is_binary(owner_user_id) and is_binary(target_user_id) do
    case RoomStore.get(room_id) do
      {:ok, %Room{owner_user_id: ^owner_user_id} = room} when not is_nil(owner_user_id) ->
        if target_user_id == room.owner_user_id do
          {:error, :owner_immutable}
        else
          case RoomStore.remove_member(room_id, target_user_id) do
            :ok ->
              RoomEvents.publish_membership_changed(room_id)
              :ok

            :not_found ->
              {:error, :member_not_found}
          end
        end

      _ ->
        {:error, :not_owner}
    end
  end

  @doc "Admit a user through a raw invite token with their member display name."
  @spec consume_invite(Room.id(), String.t(), String.t(), String.t()) ::
          {:ok, :joined} | {:error, :invalid_invite}
  def consume_invite(room_id, user_id, token, display_name)

  def consume_invite(room_id, user_id, token, display_name) when is_binary(token) do
    RoomStore.consume_invite(room_id, user_id, :crypto.hash(:sha256, token), display_name)
  end

  def consume_invite(_, _, _, _), do: {:error, :invalid_invite}

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
        :ok =
          RoomServer.add_analysis(
            pid,
            analysis_id
          )

        :telemetry.execute([:openchesslab, :room, :analysis_added], %{count: 1})
        :ok

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
        # The aggregate survives while any room or library entry still
        # references it; otherwise removing it here deletes it.
        :ok = RoomServer.remove_analysis(pid, analysis_id)
        RoomStore.cleanup_orphaned_analysis(analysis_id)
        :telemetry.execute([:openchesslab, :room, :analysis_removed], %{count: 1})
        :ok

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
        :ok = RoomStore.touch(room_id)

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

    if deleted_ids != [] do
      :telemetry.execute([:openchesslab, :room, :pruned], %{count: length(deleted_ids)})
    end

    deleted_ids
  end

  @doc """
  Prunes rooms with no activity in the last `older_than_days` days, including
  their room analyses. Library references to those analyses are materialized
  into independent copies first, so a pruned room never takes saved work with
  it. Canonical games and positions are shared corpus content and stay.
  """
  @spec prune_inactive_rooms(non_neg_integer(), pos_integer(), options()) :: [Room.id()]
  def prune_inactive_rooms(older_than_days \\ 3, limit \\ 100, opts \\ []) do
    RoomStore.inactive_room_candidates(older_than_days, limit)
    |> Enum.map(fn {room_id, analysis_ids} ->
      Enum.each(analysis_ids, &UserLibrary.materialize_analysis/1)
      :ok = RoomStore.delete_analyses(analysis_ids)
      :ok = RoomStore.delete(room_id)
      terminate_room_worker(room_id, opts)
      {room_id, length(analysis_ids)}
    end)
    |> case do
      [] ->
        []

      pruned ->
        :telemetry.execute(
          [:openchesslab, :room, :pruned],
          %{count: length(pruned)}
        )

        :telemetry.execute(
          [:openchesslab, :room, :materialized],
          %{count: Enum.sum(Enum.map(pruned, &elem(&1, 1)))}
        )

        Enum.map(pruned, &elem(&1, 0))
    end
  end

  @doc "Stamp the room as active right now (a visit, a move, a comment, chat)."
  @spec touch(Room.id()) :: :ok
  def touch(room_id), do: RoomStore.touch(room_id)

  @spec stop_room(
          Room.id(),
          options()
        ) :: :ok
  def stop_room(room_id, opts \\ []) do
    :ok = RoomStore.delete(room_id)
    :telemetry.execute([:openchesslab, :room, :stopped], %{count: 1})
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
