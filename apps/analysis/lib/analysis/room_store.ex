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
    COALESCE(
      array_agg(room_analyses.analysis_id ORDER BY room_analyses.id)
        FILTER (WHERE room_analyses.analysis_id IS NOT NULL),
      ARRAY[]::text[]
    ) AS analysis_ids
  FROM rooms
  LEFT JOIN room_analyses ON room_analyses.room_id = rooms.id
  WHERE rooms.id = $1
  GROUP BY rooms.id
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

  @spec ensure(String.t()) :: :ok
  def ensure(id) when is_binary(id) and byte_size(id) > 0 do
    Repo.query!(@create_sql, [id])
    :ok
  end

  @spec get(String.t()) :: {:ok, Room.t()} | :not_found
  def get(id) when is_binary(id) and byte_size(id) > 0 do
    case Repo.query!(@get_sql, [id]).rows do
      [[^id, analysis_ids]] -> {:ok, %Room{id: id, analysis_ids: analysis_ids}}
      [] -> :not_found
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
end
