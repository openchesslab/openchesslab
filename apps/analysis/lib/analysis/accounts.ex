defmodule Analysis.Accounts do
  @moduledoc """
  Links a verified external provider identity to an internal user.

  Only the provider and HMAC-SHA256 of its opaque subject are persisted. Never
  store the raw subject, profile name, email, OAuth token or authorization code.

  IMPORTANT: callers must first independently validate the OAuth response and
  provider identity. These functions do not authenticate external assertions.
  The HMAC key must be stable across app releases or existing links become
  unresolvable. Provision it before enabling an OAuth callback in production.
  """

  alias OpenChessLab.Repo

  @link_sql """
  INSERT INTO accounts (user_id, provider, subject_hmac)
  SELECT id, $2, $3 FROM users WHERE id = $1
  ON CONFLICT (provider, subject_hmac) DO NOTHING
  RETURNING id
  """

  @find_sql """
  SELECT id, user_id::text
  FROM accounts
  WHERE provider = $1 AND subject_hmac = $2
  """

  @list_sql """
  SELECT provider FROM accounts WHERE user_id = $1 ORDER BY provider, id
  """

  @doc "Link a provider subject already verified by a trusted OAuth flow."
  @spec link_verified(String.t(), String.t(), String.t()) ::
          {:ok, integer()} | {:error, :invalid_identity | :user_not_found | :already_linked}
  def link_verified(user_id, provider, subject)
      when is_binary(user_id) and is_binary(provider) and is_binary(subject) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         :ok <- valid_identity(provider, subject) do
      digest = subject_digest(provider, subject)

      case Repo.query!(@link_sql, [db_id, provider, digest]).rows do
        [[account_id]] ->
          {:ok, account_id}

        [] ->
          case Repo.query!(@find_sql, [provider, digest]).rows do
            [[account_id, ^user_id]] -> {:ok, account_id}
            [[_account_id, _other_user]] -> {:error, :already_linked}
            [] -> {:error, :user_not_found}
          end
      end
    else
      _ -> {:error, :invalid_identity}
    end
  end

  def link_verified(_, _, _), do: {:error, :invalid_identity}

  @doc "Resolve a provider's previously verified subject to its internal user ID."
  @spec user_for_verified_identity(String.t(), String.t()) ::
          {:ok, String.t()} | :not_found | {:error, :invalid_identity}
  def user_for_verified_identity(provider, subject)
      when is_binary(provider) and is_binary(subject) do
    with :ok <- valid_identity(provider, subject) do
      digest = subject_digest(provider, subject)

      case Repo.query!(@find_sql, [provider, digest]).rows do
        [[_account_id, user_id]] -> {:ok, user_id}
        [] -> :not_found
      end
    end
  end

  def user_for_verified_identity(_, _), do: {:error, :invalid_identity}

  @doc "Returns provider types only, not provider subject identifiers."
  @spec providers_for(String.t()) :: [String.t()]
  def providers_for(user_id) when is_binary(user_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.query!(@list_sql, [db_id]).rows |> Enum.map(fn [provider] -> provider end)

      :error ->
        []
    end
  end

  def providers_for(_), do: []

  defp valid_identity(provider, subject) do
    if Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, provider) and
         byte_size(subject) > 0 do
      :ok
    else
      {:error, :invalid_identity}
    end
  end

  defp subject_digest(provider, subject) do
    key = Application.fetch_env!(:analysis, :account_subject_hmac_key)

    if not is_binary(key) or byte_size(key) < 32 do
      raise ArgumentError, "account_subject_hmac_key must contain at least 32 bytes"
    end

    :crypto.mac(:hmac, :sha256, key, provider <> <<0>> <> subject)
  end
end
