defmodule Analysis.UserSessions do
  @moduledoc """
  Revocable PostgreSQL sessions for internal users, with a fixed 24-hour lifetime.

  Only a SHA-256 digest of a fresh 256-bit random credential is persisted.
  `create/1` is a trusted operation: its caller must independently authenticate
  the user first. A user ID supplied by a browser is never authentication.

  The returned token is a bearer secret. Never log it or put it in URLs. The web
  boundary must renew the browser session on login, use secure cookies, and
  resolve the token on protected requests and LiveView events. This module
  does not implement OAuth, cookies, authorization or LiveView disconnection.
  """

  alias OpenChessLab.Repo

  @insert_sql """
  INSERT INTO user_sessions (token_hash, user_id, created_at, expires_at)
  SELECT $1, id, timezone('UTC', statement_timestamp()),
         timezone('UTC', statement_timestamp()) + interval '24 hours'
  FROM users WHERE id = $2
  RETURNING expires_at
  """

  @resolve_sql """
  SELECT users.id::text, users.created_at
  FROM user_sessions JOIN users ON users.id = user_sessions.user_id
  WHERE token_hash = $1 AND expires_at > timezone('UTC', statement_timestamp())
  """

  @doc "Issue a new credential only after trusted authentication."
  @spec create(String.t()) ::
          {:ok, %{token: String.t(), expires_at: NaiveDateTime.t()}}
          | {:error, :user_not_found}
  def create(user_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

        case Repo.query!(@insert_sql, [digest(token), db_id], log: false).rows do
          [[expires_at]] -> {:ok, %{token: token, expires_at: expires_at}}
          [] -> {:error, :user_not_found}
        end

      :error ->
        {:error, :user_not_found}
    end
  end

  @doc "Resolve a bearer credential; invalid, expired and revoked tokens fail closed."
  @spec user_for_token(term()) :: {:ok, Analysis.Users.user()} | :not_found
  def user_for_token(token) do
    if valid_token?(token) do
      case Repo.query!(@resolve_sql, [digest(token)], log: false).rows do
        [[id, created_at]] -> {:ok, %{id: id, created_at: created_at}}
        [] -> :not_found
      end
    else
      :not_found
    end
  end

  @doc "Idempotently revoke one session, including an expired session."
  @spec revoke(term()) :: :ok
  def revoke(token) do
    if valid_token?(token) do
      Repo.query!("DELETE FROM user_sessions WHERE token_hash = $1", [digest(token)], log: false)
    end

    :ok
  end

  @doc "Revoke all sessions for a user; for trusted account-security flows only."
  @spec revoke_all(String.t()) :: :ok
  def revoke_all(user_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.query!("DELETE FROM user_sessions WHERE user_id = $1", [db_id], log: false)

      :error ->
        :ok
    end

    :ok
  end

  defp valid_token?(token) when is_binary(token) and byte_size(token) == 43 do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == 32 ->
        Base.url_encode64(raw, padding: false) == token

      _ ->
        false
    end
  end

  defp valid_token?(_), do: false

  defp digest(token), do: :crypto.hash(:sha256, token)
end
