defmodule Analysis.ProviderGrants do
  @moduledoc """
  Stored OAuth grants: one provider access token per user per provider,
  encrypted at rest with AES-256-GCM under a dedicated server key
  (`:analysis, :provider_grant_key`).

  Grants exist so the user can act at the provider (currently: importing the
  user's own public Lichess games). A grant is written on every successful
  Lichess login or link, deleted on unlink, when the provider rejects the
  token, or with the account (FK cascade). Tokens are never logged.

  The key must be stable across releases or stored grants become unreadable;
  unreadable or tampered grants read as `:not_found`.
  """

  alias OpenChessLab.Repo

  @aad "provider-grant-v1"
  @iv_bytes 12
  @tag_bytes 16

  @upsert_sql """
  INSERT INTO provider_grants (user_id, provider, token_encrypted, granted_at, updated_at)
  VALUES ($1, $2, $3, now(), now())
  ON CONFLICT (user_id, provider)
  DO UPDATE SET token_encrypted = $3, updated_at = now()
  """

  @spec put(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def put(user_id, provider, token)
      when is_binary(user_id) and is_binary(provider) and is_binary(token) do
    with {:ok, db_user} <- Ecto.UUID.dump(user_id) do
      Repo.query!(@upsert_sql, [db_user, provider, encrypt(token)], log: false)
      :ok
    end
  end

  @spec get_token(String.t(), String.t()) :: {:ok, String.t()} | :not_found
  def get_token(user_id, provider) when is_binary(user_id) and is_binary(provider) do
    with {:ok, db_user} <- Ecto.UUID.dump(user_id),
         [[blob]] <-
           Repo.query!(
             "SELECT token_encrypted FROM provider_grants WHERE user_id = $1 AND provider = $2",
             [db_user, provider],
             log: false
           ).rows,
         plaintext when is_binary(plaintext) <- decrypt(blob) do
      {:ok, plaintext}
    else
      _ -> :not_found
    end
  end

  @spec has?(String.t(), String.t()) :: boolean()
  def has?(user_id, provider), do: get_token(user_id, provider) != :not_found

  @spec delete(String.t(), String.t()) :: :ok
  def delete(user_id, provider) when is_binary(user_id) and is_binary(provider) do
    with {:ok, db_user} <- Ecto.UUID.dump(user_id) do
      Repo.query!(
        "DELETE FROM provider_grants WHERE user_id = $1 AND provider = $2",
        [db_user, provider],
        log: false
      )
    end

    :ok
  end

  # --- Library sync (opt-in) -------------------------------------------------

  @doc "Enable or disable library sync for this user's provider grant."
  @spec set_sync_enabled(String.t(), String.t(), boolean()) :: :ok | :not_found
  def set_sync_enabled(user_id, provider, enabled) when is_boolean(enabled) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        Repo.query!(
          "UPDATE provider_grants SET sync_enabled = $3, updated_at = now() WHERE user_id = $1 AND provider = $2",
          [db_user, provider, enabled],
          log: false
        )
        |> case do
          %{num_rows: 0} -> :not_found
          _ -> :ok
        end

      _ ->
        :not_found
    end
  end

  @doc "Sync state for one grant: whether it is enabled, the cursor, last sync."
  @spec sync_state(String.t(), String.t()) ::
          {:ok, %{enabled: boolean(), cursor: integer() | nil, synced_at: term()}} | :not_found
  def sync_state(user_id, provider) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        case Repo.query!(
               "SELECT sync_enabled, sync_cursor, synced_at FROM provider_grants WHERE user_id = $1 AND provider = $2",
               [db_user, provider],
               log: false
             ).rows do
          [[enabled, cursor, synced_at]] ->
            {:ok, %{enabled: enabled, cursor: cursor, synced_at: synced_at}}

          [] ->
            :not_found
        end

      _ ->
        :not_found
    end
  end

  @doc "Every user with sync enabled for this provider, with their cursor."
  @spec list_sync_enabled(String.t()) :: [%{user_id: String.t(), cursor: integer() | nil}]
  def list_sync_enabled(provider) do
    Repo.query!(
      "SELECT user_id::text, sync_cursor FROM provider_grants WHERE provider = $1 AND sync_enabled",
      [provider],
      log: false
    ).rows
    |> Enum.map(fn [user_id, cursor] -> %{user_id: user_id, cursor: cursor} end)
  end

  @doc "Advance the sync watermark after a page was imported; stamps synced_at."
  @spec advance_cursor(String.t(), String.t(), integer()) :: :ok
  def advance_cursor(user_id, provider, cursor) when is_integer(cursor) do
    with {:ok, db_user} <- Ecto.UUID.dump(user_id) do
      Repo.query!(
        "UPDATE provider_grants SET sync_cursor = $3, synced_at = now() WHERE user_id = $1 AND provider = $2",
        [db_user, provider, cursor],
        log: false
      )
    end

    :ok
  end

  defp encrypt(plaintext) do
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, @aad, true)
    iv <> tag <> cipher
  end

  defp decrypt(<<iv::binary-@iv_bytes, tag::binary-@tag_bytes, cipher::binary>>) do
    :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, cipher, @aad, tag, false)
  end

  defp key do
    :crypto.hash(:sha256, Application.fetch_env!(:analysis, :provider_grant_key))
  end
end
