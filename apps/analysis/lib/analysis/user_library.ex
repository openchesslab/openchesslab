defmodule Analysis.UserLibrary do
  @moduledoc """
  A user's saved references to existing analyses. Removing a reference does not
  delete the underlying analysis or remove it from another user's library.

  Callers must authenticate and authorize the user before invoking this API.
  """

  alias OpenChessLab.Repo

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
