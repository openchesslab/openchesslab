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
        [db_user, provider], log: false)
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
