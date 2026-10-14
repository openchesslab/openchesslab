defmodule Analysis.UserLibrary do
  @moduledoc """
  A user's saved analyses. Room saves create independent copies. Removing a reference does not
  delete the underlying analysis or remove it from another user's library.

  Callers must authenticate and authorize the user before invoking this API.
  """

  alias Analysis.AnalysisStore
  alias OpenChessLab.Repo

  @copy_source_sql """
  SELECT a.analysis_id
  FROM room_analyses AS ra
  JOIN analyses AS a ON a.analysis_id = ra.analysis_id
  WHERE ra.room_id = $1 AND ra.analysis_id = $2
  FOR SHARE OF ra, a
  """

  @doc """
  Save a fresh snapshot of a room analysis in this user's library atomically.
  The caller authenticates the user and authorizes access to the room; the
  transaction checks durable membership and holds it through the copy. Nothing
  is added to the room or broadcast. Repeated calls create separate snapshots.
  """
  @spec copy_from_room(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_identity | :user_not_found | :analysis_not_found}
  def copy_from_room(user_id, room_id, analysis_id)
      when is_binary(room_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.transaction(fn ->
          if Repo.query!("SELECT id FROM users WHERE id = $1 FOR KEY SHARE", [db_id]).rows == [] do
            Repo.rollback(:user_not_found)
          end

          if Repo.query!(@copy_source_sql, [room_id, analysis_id]).rows == [] do
            Repo.rollback(:analysis_not_found)
          end

          {:ok, source, _revision} = AnalysisStore.get(analysis_id)
          id = "analysis-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
          {:ok, 1} = AnalysisStore.insert(%{source | id: id})
          :ok = save(user_id, id)
          id
        end)

      :error ->
        {:error, :invalid_identity}
    end
  end

  def copy_from_room(_, _, _), do: {:error, :invalid_identity}

  @save_sql """
  INSERT INTO user_analyses (user_id, analysis_id)
  SELECT users.id, analyses.analysis_id
  FROM users CROSS JOIN analyses
  WHERE users.id = $1 AND analyses.analysis_id = $2
  ON CONFLICT (user_id, analysis_id) DO NOTHING
  RETURNING id
  """

  @exists_sql """
  SELECT EXISTS (SELECT 1 FROM users WHERE id = $1),
         EXISTS (SELECT 1 FROM analyses WHERE analysis_id = $2)
  """

  @list_sql """
  SELECT analysis_id FROM user_analyses
  WHERE user_id = $1
  ORDER BY created_at, id
  """

  @remove_sql """
  DELETE FROM user_analyses WHERE user_id = $1 AND analysis_id = $2
  RETURNING id
  """

  @doc "Idempotently save a reference to an existing analysis."
  @spec save(String.t(), String.t()) ::
          :ok | {:error, :user_not_found | :analysis_not_found | :invalid_identity}
  def save(user_id, analysis_id) when is_binary(user_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        case Repo.query!(@save_sql, [db_id, analysis_id]).rows do
          [[_id]] ->
            :ok

          [] ->
            [[user_exists, analysis_exists]] = Repo.query!(@exists_sql, [db_id, analysis_id]).rows

            cond do
              not user_exists -> {:error, :user_not_found}
              not analysis_exists -> {:error, :analysis_not_found}
              true -> :ok
            end
        end

      :error ->
        {:error, :invalid_identity}
    end
  end

  def save(_, _), do: {:error, :invalid_identity}

  @spec list(String.t()) :: [String.t()]
  def list(user_id) when is_binary(user_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.query!(@list_sql, [db_id]).rows |> Enum.map(fn [analysis_id] -> analysis_id end)

      :error ->
        []
    end
  end

  def list(_), do: []

  @doc "Read at most 50 saved references, using the existing user/analysis unique index for keyset paging."
  @spec page(String.t(), String.t() | nil) :: %{entries: [map()], next_cursor: String.t() | nil}
  def page(user_id, after_id \\ nil) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         true <- is_nil(after_id) or is_binary(after_id) do
      {predicate, params} =
        if is_nil(after_id), do: {"", [db_id]}, else: {" AND analysis_id > $2", [db_id, after_id]}

      rows =
        Repo.query!(
          "SELECT analysis_id, created_at FROM user_analyses WHERE user_id = $1" <>
            predicate <> " ORDER BY analysis_id LIMIT 51",
          params
        ).rows

      entries =
        Enum.map(Enum.take(rows, 50), fn [id, saved_at] -> %{id: id, saved_at: saved_at} end)

      cursor = if length(rows) > 50, do: List.last(entries).id
      %{entries: entries, next_cursor: cursor}
    else
      _ -> %{entries: [], next_cursor: nil}
    end
  end

  @doc "Remove only this user's saved reference, never the analysis."
  @spec remove(String.t(), String.t()) :: :ok | :not_found
  def remove(user_id, analysis_id) when is_binary(user_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        case Repo.query!(@remove_sql, [db_id, analysis_id]).rows do
          [[_id]] -> :ok
          [] -> :not_found
        end

      :error ->
        :not_found
    end
  end

  def remove(_, _), do: :not_found
end
