defmodule Analysis.Users do
  @moduledoc """
  Internal user identities, deliberately without names, email addresses or passwords.

  A user is created only by a trusted application flow. Owning a user ID is not
  authentication, and this module must not be exposed directly as a public API.
  """

  alias OpenChessLab.Repo

  @type user :: %{id: String.t(), created_at: NaiveDateTime.t()}

  @insert_sql """
  INSERT INTO users DEFAULT VALUES
  RETURNING id::text, created_at
  """

  @get_sql """
  SELECT id::text, created_at FROM users WHERE id = $1
  """

  @delete_sql """
  DELETE FROM users WHERE id = $1 RETURNING id::text
  """

  @spec create() :: {:ok, user()}
  def create do
    [[id, created_at]] = Repo.query!(@insert_sql, []).rows
    {:ok, %{id: id, created_at: created_at}}
  end

  @spec get(String.t()) :: {:ok, user()} | :not_found
  def get(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, db_id} ->
        case Repo.query!(@get_sql, [db_id]).rows do
          [[user_id, created_at]] -> {:ok, %{id: user_id, created_at: created_at}}
          [] -> :not_found
        end

      :error ->
        :not_found
    end
  end

  def get(_), do: :not_found

  @doc "Delete an identity and its provider accounts/library references, not analyses."
  @spec delete(String.t()) :: :ok | :not_found
  def delete(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, db_id} ->
        case Repo.query!(@delete_sql, [db_id]).rows do
          [[_]] -> :ok
          [] -> :not_found
        end

      :error ->
        :not_found
    end
  end

  def delete(_), do: :not_found
end
