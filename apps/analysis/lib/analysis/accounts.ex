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

  alias Analysis.Users
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

  # The unique constraint arbitrates races, including concurrent explicit links.
  # The conflict branch MUST preserve the existing owner, never EXCLUDED.user_id.
  @resolve_link_sql """
  INSERT INTO accounts (user_id, provider, subject_hmac)
  VALUES ($1, $2, $3)
  ON CONFLICT (provider, subject_hmac)
  DO UPDATE SET user_id = accounts.user_id
  RETURNING user_id::text
  """

  @doc """
  Find or create the internal user for an independently verified provider identity.

  This is a trusted login operation, not OAuth verification or account linking.
  Never call it with a browser's claimed provider subject. It does not accept a
  target user ID and never merges users or moves an existing account.

  User/account creation is atomic and participates in a caller's transaction,
  allowing subsequent session issuance to roll back together. Concurrent first
  logins converge on the unique account owner without leaving unused users.
  Database failures raise and roll back; invalid identities return an error.
  """
  @spec resolve_verified(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_identity}
  def resolve_verified(provider, subject) when is_binary(provider) and is_binary(subject) do
    with :ok <- valid_identity(provider, subject) do
      digest = subject_digest(provider, subject)

      Repo.transact(fn ->
        case Repo.query!(@find_sql, [provider, digest], log: false).rows do
          [[_account_id, user_id]] ->
            {:ok, user_id}

          [] ->
            {:ok, candidate} = Users.create()

            [[owner_id]] =
              Repo.query!(
                @resolve_link_sql,
                [Ecto.UUID.dump!(candidate.id), provider, digest],
                log: false
              ).rows

            if owner_id != candidate.id, do: Users.delete(candidate.id)
            {:ok, owner_id}
        end
      end)
    end
  end

  def resolve_verified(_, _), do: {:error, :invalid_identity}

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

  @lock_providers_sql """
  SELECT provider FROM accounts WHERE user_id = $1 ORDER BY provider FOR UPDATE
  """

  @doc """
  Unlink every identity of one provider from the user, never the last provider.

  There is no account recovery, email or password: unlinking the only remaining
  provider would permanently lock the user out, so it fails with `:last_identity`.
  The user's identity rows are locked first, so concurrent unlinks can never
  strip the final identity together. Callers must authenticate the user first;
  a supplied user ID is not authentication. Sessions are untouched: an unlinked
  user stays signed in and can relink the same provider identity later.
  """
  @spec unlink(String.t(), String.t()) ::
          {:ok, non_neg_integer()}
          | {:error, :not_linked | :last_identity | :invalid_identity}
  def unlink(user_id, provider) when is_binary(user_id) and is_binary(provider) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         :ok <- valid_provider(provider) do
      Repo.transact(fn ->
        providers =
          Repo.query!(@lock_providers_sql, [db_id], log: false).rows
          |> List.flatten()
          |> Enum.uniq()

        cond do
          provider not in providers ->
            Repo.rollback(:not_linked)

          providers == [provider] ->
            Repo.rollback(:last_identity)

          true ->
            result =
              Repo.query!(
                "DELETE FROM accounts WHERE user_id = $1 AND provider = $2",
                [db_id, provider],
                log: false
              )

            {:ok, result.num_rows}
        end
      end)
    else
      _ -> {:error, :invalid_identity}
    end
  end

  def unlink(_, _), do: {:error, :invalid_identity}

  defp valid_identity(provider, subject) do
    with :ok <- valid_provider(provider),
         true <- byte_size(subject) > 0 do
      :ok
    else
      _ -> {:error, :invalid_identity}
    end
  end

  defp valid_provider(provider) do
    if Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, provider) do
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
