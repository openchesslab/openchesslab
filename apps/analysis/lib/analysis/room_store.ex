defmodule Analysis.RoomStore do
  @moduledoc """
  Durable rooms and ordered analysis memberships in PostgreSQL.

  The room process caches membership for realtime broadcasts, but PostgreSQL
  is authoritative across application restarts. Chat remains ephemeral.
  """

  alias Analysis.Room
  alias OpenChessLab.Repo

  @create_sql """
  INSERT INTO rooms (id)
  VALUES ($1)
  ON CONFLICT (id) DO NOTHING
  """

  @create_unique_sql """
  INSERT INTO rooms (id)
  VALUES ($1)
  ON CONFLICT (id) DO NOTHING
  RETURNING id
  """

  @get_sql """
  SELECT
    rooms.id,
    rooms.owner_user_id::text,
    COALESCE(
      array_agg(room_analyses.analysis_id ORDER BY room_analyses.id)
        FILTER (WHERE room_analyses.analysis_id IS NOT NULL),
      ARRAY[]::text[]
    ) AS analysis_ids
  FROM rooms
  LEFT JOIN room_analyses ON room_analyses.room_id = rooms.id
  WHERE rooms.id = $1
  GROUP BY rooms.id, rooms.owner_user_id
  """

  @add_analysis_sql """
  INSERT INTO room_analyses (room_id, analysis_id)
  SELECT id, $2 FROM rooms WHERE id = $1
  ON CONFLICT (room_id, analysis_id) DO NOTHING
  """

  @remove_analysis_sql """
  DELETE FROM room_analyses
  WHERE room_id = $1 AND analysis_id = $2
  """

  @delete_sql """
  DELETE FROM rooms WHERE id = $1
  """

  @prune_old_empty_sql """
  WITH candidates AS (
    SELECT rooms.id
    FROM rooms
    WHERE rooms.created_at < now() - ($1::integer * INTERVAL '1 day')
      AND NOT EXISTS (
        SELECT 1 FROM room_analyses WHERE room_analyses.room_id = rooms.id
      )
    ORDER BY rooms.created_at, rooms.id
    LIMIT $2
    FOR UPDATE OF rooms SKIP LOCKED
  )
  DELETE FROM rooms
  USING candidates
  WHERE rooms.id = candidates.id
  RETURNING rooms.id
  """

  @doc "Atomically reserve a fresh room code without joining an existing room."
  @spec create(String.t()) :: :ok | {:error, :already_exists}
  def create(id) when is_binary(id) and byte_size(id) > 0 do
    case Repo.query!(@create_unique_sql, [id]).rows do
      [[^id]] -> :ok
      [] -> {:error, :already_exists}
    end
  end

  @create_private_sql """
  INSERT INTO rooms (id, owner_user_id)
  VALUES ($1, $2)
  ON CONFLICT (id) DO NOTHING
  RETURNING id
  """

  @insert_owner_sql """
  INSERT INTO room_members (room_id, user_id, display_name)
  VALUES ($1, $2, $3)
  ON CONFLICT (room_id, user_id) DO NOTHING
  """

  @doc """
  Atomically reserve a fresh private room and make the owner its first member.

  The room code alone never grants entry; only the owner and rows in
  `room_members` see the room. Callers authenticate the owner user first.
  The display name is a server-generated, non-PII label for member listing.
  """
  @spec create_private(String.t(), String.t(), String.t()) ::
          :ok | {:error, :already_exists | :invalid_owner}
  def create_private(id, owner_user_id, display_name)
      when is_binary(id) and byte_size(id) > 0 and is_binary(owner_user_id) and
             is_binary(display_name) do
    case Ecto.UUID.dump(owner_user_id) do
      {:ok, db_owner} ->
        Repo.transaction(fn ->
          case Repo.query!(@create_private_sql, [id, db_owner]).rows do
            [[^id]] ->
              Repo.query!(@insert_owner_sql, [id, db_owner, display_name])
              :ok

            [] ->
              Repo.rollback(:already_exists)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, :already_exists} = error -> error
        end

      _ ->
        {:error, :invalid_owner}
    end
  end

  @member_sql """
  SELECT EXISTS (
    SELECT 1 FROM room_members WHERE room_id = $1 AND user_id = $2
  )
  """

  @doc "Is this user a member of the room? Owners become members at creation."
  @spec member?(String.t(), String.t() | nil) :: boolean()
  def member?(room_id, user_id) when is_binary(room_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        [[member]] = Repo.query!(@member_sql, [room_id, db_user], log: false).rows
        member

      :error ->
        false
    end
  end

  @add_member_sql """
  INSERT INTO room_members (room_id, user_id, display_name)
  SELECT id, $2, $3 FROM rooms WHERE id = $1
  ON CONFLICT (room_id, user_id) DO NOTHING
  RETURNING room_id
  """

  @doc "Idempotently add a member to a durable room with a server-generated label."
  @spec add_member(String.t(), String.t(), String.t()) ::
          :ok | {:error, :room_not_found}
  def add_member(room_id, user_id, display_name)
      when is_binary(room_id) and is_binary(display_name) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        case Repo.query!(@add_member_sql, [room_id, db_user, display_name]).rows do
          [[_room_id]] -> :ok
          [] -> {:error, :room_not_found}
        end

      _ ->
        {:error, :room_not_found}
    end
  end

  @members_sql """
  SELECT user_id::text, display_name, created_at
  FROM room_members
  WHERE room_id = $1
  ORDER BY created_at, user_id
  """

  @doc """
  The durable member list of a room, oldest join first.

  Display names are server-generated labels without personal data; they are
  never unique identifiers or proof of authentication.
  """
  @spec members(String.t()) :: [
          %{user_id: String.t(), display_name: String.t(), joined_at: NaiveDateTime.t()}
        ]
  def members(room_id) when is_binary(room_id) do
    Repo.query!(@members_sql, [room_id], log: false).rows
    |> Enum.map(fn [user_id, display_name, joined_at] ->
      %{user_id: user_id, display_name: display_name, joined_at: joined_at}
    end)
  end

  @remove_member_sql """
  DELETE FROM room_members
  WHERE room_id = $1 AND user_id = $2
  RETURNING user_id
  """

  @doc "Remove one membership row; the caller owns the owner/authority checks."
  @spec remove_member(String.t(), String.t()) :: :ok | :not_found
  def remove_member(room_id, user_id) when is_binary(room_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        case Repo.query!(@remove_member_sql, [room_id, db_user], log: false).rows do
          [[_user_id]] -> :ok
          [] -> :not_found
        end

      _ ->
        :not_found
    end
  end

  @revoke_invites_sql """
  UPDATE room_invites
  SET revoked_at = now()
  WHERE room_id = $1 AND revoked_at IS NULL
  """

  @insert_invite_sql """
  INSERT INTO room_invites (token_hash, room_id)
  VALUES ($1, $2)
  """

  @doc """
  Rotate the room's invite: revoke every active link, then store one fresh
  token hash. The raw token never enters PostgreSQL; only its SHA-256 hash
  is durable, so it is shown to the owner once at generation.
  """
  @spec create_invite(String.t(), binary()) :: :ok
  def create_invite(room_id, token_hash) when byte_size(token_hash) == 32 do
    Repo.transaction(fn ->
      Repo.query!(@revoke_invites_sql, [room_id])
      Repo.query!(@insert_invite_sql, [token_hash, room_id])
      :ok
    end)
    |> elem(1)
  end

  @doc "Revoke every active invite link of the room; new joins stop immediately."
  @spec revoke_invites(String.t()) :: non_neg_integer()
  def revoke_invites(room_id) do
    Repo.query!(@revoke_invites_sql, [room_id]).num_rows
  end

  @active_invite_sql """
  SELECT EXISTS (
    SELECT 1 FROM room_invites WHERE room_id = $1 AND revoked_at IS NULL
  )
  """

  @doc "Does the room have an active (non-revoked) invite link?"
  @spec invite_active?(String.t()) :: boolean()
  def invite_active?(room_id) when is_binary(room_id) do
    [[active]] = Repo.query!(@active_invite_sql, [room_id], log: false).rows
    active
  end

  @consume_invite_sql """
  SELECT token_hash
  FROM room_invites
  WHERE room_id = $1 AND token_hash = $2 AND revoked_at IS NULL
  FOR UPDATE
  """

  @doc """
  Atomically admit a user through an active invite.

  The invite row is locked before the membership insert, so a concurrent
  revoke cannot admit anyone after cutoff. Idempotent per user; the raw
  token is only ever hashed here. Callers authenticate the joining user.
  """
  @spec consume_invite(String.t(), String.t(), binary(), String.t()) ::
          {:ok, :joined} | {:error, :invalid_invite}
  def consume_invite(room_id, user_id, token_hash, display_name)
      when is_binary(room_id) and byte_size(token_hash) == 32 and is_binary(display_name) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        Repo.transaction(fn ->
          case Repo.query!(@consume_invite_sql, [room_id, token_hash], log: false).rows do
            [[_token_hash]] ->
              Repo.query!(@add_member_sql, [room_id, db_user, display_name], log: false)
              :joined

            [] ->
              Repo.rollback(:invalid_invite)
          end
        end)
        |> case do
          {:ok, :joined} -> {:ok, :joined}
          {:error, :invalid_invite} = error -> error
        end

      _ ->
        {:error, :invalid_invite}
    end
  end

  @spec ensure(String.t()) :: :ok
  def ensure(id) when is_binary(id) and byte_size(id) > 0 do
    Repo.query!(@create_sql, [id])
    :ok
  end

  @spec get(String.t()) :: {:ok, Room.t()} | :not_found
  def get(id) when is_binary(id) and byte_size(id) > 0 do
    case Repo.query!(@get_sql, [id]).rows do
      [[^id, owner_user_id, analysis_ids]] ->
        {:ok, %Room{id: id, analysis_ids: analysis_ids, owner_user_id: owner_user_id}}

      [] ->
        :not_found
    end
  end

  def get(_id), do: :not_found

  @spec add_analysis(String.t(), String.t()) :: :ok
  def add_analysis(id, analysis_id) do
    Repo.query!(@add_analysis_sql, [id, analysis_id])
    :ok
  end

  @spec remove_analysis(String.t(), String.t()) :: :ok
  def remove_analysis(id, analysis_id) do
    Repo.query!(@remove_analysis_sql, [id, analysis_id])
    :ok
  end

  @doc "Atomically deletes a bounded batch of old rooms without analyses."
  @spec prune_old_empty_rooms(non_neg_integer(), pos_integer()) :: [String.t()]
  def prune_old_empty_rooms(older_than_days, limit)
      when is_integer(older_than_days) and older_than_days >= 0 and is_integer(limit) and
             limit >= 1 and limit <= 1_000 do
    Repo.query!(@prune_old_empty_sql, [older_than_days, limit]).rows
    |> Enum.map(fn [room_id] -> room_id end)
  end

  @spec delete(String.t()) :: :ok
  def delete(id) when is_binary(id) do
    Repo.query!(@delete_sql, [id])
    :ok
  end

  @doc "Stamp the room as active right now (a visit, a move, a comment, chat)."
  @spec touch(String.t()) :: :ok
  def touch(id) when is_binary(id) do
    Repo.query!("UPDATE rooms SET last_active_at = now() WHERE id = $1", [id], log: false)
    :ok
  end

  @doc """
  Rooms with no activity in the last `older_than_days` days, oldest first,
  with their analysis ids. Bounded; the caller materializes library
  references and deletes each room.
  """
  @spec inactive_room_candidates(non_neg_integer(), pos_integer()) ::
          [{String.t(), [String.t()]}]
  def inactive_room_candidates(older_than_days, limit)
      when is_integer(older_than_days) and older_than_days >= 0 and is_integer(limit) and
             limit >= 1 and limit <= 1_000 do
    Repo.query!(
      """
      SELECT r.id, COALESCE(array_agg(ra.analysis_id) FILTER (WHERE ra.analysis_id IS NOT NULL), ARRAY[]::text[])
      FROM rooms AS r
      LEFT JOIN room_analyses AS ra ON ra.room_id = r.id
      WHERE r.last_active_at < now() - make_interval(days => $1)
      GROUP BY r.id
      ORDER BY r.last_active_at
      LIMIT $2
      """,
      [older_than_days, limit]
    ).rows
    |> Enum.map(fn [room_id, analysis_ids] -> {room_id, analysis_ids} end)
  end

  @doc "Delete the room's own analysis aggregates (canonical content is shared and stays)."
  @spec delete_analyses([String.t()]) :: :ok
  def delete_analyses(analysis_ids) when is_list(analysis_ids) do
    if analysis_ids != [] do
      Repo.query!("DELETE FROM analyses WHERE analysis_id = ANY($1::text[])", [analysis_ids])
    end

    :ok
  end

  # Removing an analysis from its last room is only then a deletion: as long
  # as any room or library entry still references it, the aggregate stays.
  # The conditional delete is a single statement, so a concurrent add that
  # commits first is seen; an add that commits afterwards can leave a
  # room_analyses row behind (there is no FK on it), which the room UI
  # already renders as an unavailable analysis.
  @cleanup_orphaned_sql """
  DELETE FROM analyses
  WHERE analysis_id = $1
    AND NOT EXISTS (
      SELECT 1 FROM room_analyses WHERE room_analyses.analysis_id = analyses.analysis_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM user_analyses WHERE user_analyses.analysis_id = analyses.analysis_id
    )
  """

  @doc "Deletes the analysis aggregate when nothing references it any more."
  @spec cleanup_orphaned_analysis(String.t()) :: :ok
  def cleanup_orphaned_analysis(analysis_id) when is_binary(analysis_id) do
    Repo.query!(@cleanup_orphaned_sql, [analysis_id])
    :ok
  end
end
