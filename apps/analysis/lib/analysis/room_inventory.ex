defmodule Analysis.RoomInventory do
  @moduledoc """
  Read-only PostgreSQL inventory for room retention.

  Rooms have a durable creation timestamp. Age is not the same as inactivity:
  only rooms without any attached analyses are cleanup candidates.
  """

  alias OpenChessLab.Repo

  @default_age_days 30
  @default_limit 100
  @max_limit 1_000

  @summary_sql """
  SELECT
    COUNT(*)::bigint,
    COUNT(*) FILTER (WHERE has_analyses)::bigint,
    COUNT(*) FILTER (WHERE NOT has_analyses)::bigint,

    COUNT(*) FILTER (
      WHERE NOT has_analyses

        AND created_at < now() - ($1::integer * INTERVAL '1 day')
    )::bigint
  FROM (
    SELECT
      rooms.created_at,
      EXISTS (
        SELECT 1
        FROM room_analyses
        WHERE room_analyses.room_id = rooms.id
      ) AS has_analyses
    FROM rooms
  ) AS inventory
  """

  @old_empty_sql """
  SELECT
    rooms.id,
    EXTRACT(EPOCH FROM rooms.created_at)::bigint
  FROM rooms
  WHERE rooms.created_at < now() - ($1::integer * INTERVAL '1 day')
    AND NOT EXISTS (
      SELECT 1
      FROM room_analyses
      WHERE room_analyses.room_id = rooms.id
    )
  ORDER BY rooms.created_at, rooms.id
  LIMIT $2
  """

  @type summary :: %{
          older_than_days: non_neg_integer(),
          total_rooms: non_neg_integer(),
          rooms_with_analyses: non_neg_integer(),
          empty_rooms: non_neg_integer(),
          old_empty_rooms: non_neg_integer()
        }

  @doc "Summarizes rooms without changing or deleting any of them."
  @spec summary(non_neg_integer()) :: summary()
  def summary(older_than_days \\ @default_age_days)
      when is_integer(older_than_days) and older_than_days >= 0 do
    [[total, with_analyses, empty, old_empty]] =
      Repo.query!(@summary_sql, [older_than_days]).rows

    %{
      older_than_days: older_than_days,
      total_rooms: total,
      rooms_with_analyses: with_analyses,
      empty_rooms: empty,
      old_empty_rooms: old_empty
    }
  end

  @doc """
  Lists at most `limit` empty rooms created more than `older_than_days`
  ago. Creation dates are Unix seconds. The function does not delete rooms.
  """
  @spec old_empty_rooms(non_neg_integer(), pos_integer()) ::
          [%{id: String.t(), created_at_unix: integer()}]
  def old_empty_rooms(older_than_days \\ @default_age_days, limit \\ @default_limit)
      when is_integer(older_than_days) and older_than_days >= 0 and is_integer(limit) and
             limit >= 1 and limit <= @max_limit do
    Repo.query!(@old_empty_sql, [older_than_days, limit]).rows
    |> Enum.map(fn [id, created_at_unix] ->
      %{id: id, created_at_unix: created_at_unix}
    end)
  end
end
