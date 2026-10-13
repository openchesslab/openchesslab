defmodule Web.LichessOAuthAttempts do
  @moduledoc """
  Five-minute, single-use Lichess login attempts with S256 PKCE.

  The independent random state is public; the encrypted `browser_token` is a
  secret containing the verifier. PostgreSQL stores only hashes and timestamps.
  Encryption uses the endpoint's secret key base with a dedicated purpose salt.

  The future HTTP boundary must put `browser_token` in an HttpOnly, Secure,
  SameSite=Lax cookie, read it ONLY from that cookie, and clear it on callback.
  Never accept it from callback parameters or put it in URLs, HTML or logs.
  Initiation must be CSRF-protected. Only `authorization_params` may go to
  Lichess, alongside the server-configured client ID and redirect URI.

  Consume before exchanging a code, including on provider denial. Consumption
  commits independently of later login work; retries require a new attempt.
  No identity is authenticated here, and this is not an account-linking flow.
  """

  alias OpenChessLab.Repo

  @salt "lichess-login-attempt"
  @max_age 300

  @insert_sql """
  INSERT INTO lichess_oauth_attempts (state_hash, browser_token_hash, created_at, expires_at)
  VALUES ($1, $2, timezone('UTC', statement_timestamp()),
          timezone('UTC', statement_timestamp()) + interval '5 minutes')
  RETURNING expires_at
  """

  # Check the clock after acquiring/deleting the row, even if a row lock delayed us.
  @consume_sql """
  DELETE FROM lichess_oauth_attempts
  WHERE state_hash = $1 AND browser_token_hash = $2
  RETURNING expires_at > timezone('UTC', clock_timestamp())
  """

  @prune_sql """
  WITH expired AS (
    SELECT state_hash FROM lichess_oauth_attempts
    WHERE expires_at <= timezone('UTC', statement_timestamp())
    ORDER BY expires_at, state_hash
    LIMIT 1000
    FOR UPDATE SKIP LOCKED
  )
  DELETE FROM lichess_oauth_attempts USING expired
  WHERE lichess_oauth_attempts.state_hash = expired.state_hash
  """

  @doc "Create independent state and verifier; only the S256 challenge is public."
  @spec create() ::
          {:ok,
           %{
             authorization_params: %{String.t() => String.t()},
             browser_token: String.t(),
             expires_at: NaiveDateTime.t()
           }}
  def create do
    state = random_secret()
    verifier = random_secret()
    browser_token = Phoenix.Token.encrypt(Web.Endpoint, @salt, verifier, max_age: @max_age)
    prune_expired()

    [[expires_at]] =
      Repo.query!(@insert_sql, [hash(state), hash(browser_token)], log: false).rows

    {:ok,
     %{
       authorization_params: %{
         "state" => state,
         "code_challenge" => Base.url_encode64(hash(verifier), padding: false),
         "code_challenge_method" => "S256"
       },
       browser_token: browser_token,
       expires_at: expires_at
     }}
  end

  @doc "Consume once using callback state and the initiating browser's secret cookie."
  @spec consume(term(), term()) :: {:ok, String.t()} | {:error, :invalid_attempt}
  def consume(state, browser_token) do
    if Repo.in_transaction?() do
      raise ArgumentError, "OAuth attempts must be consumed outside a transaction"
    end

    with true <- valid_secret?(state),
         true <- is_binary(browser_token) and byte_size(browser_token) in 1..2048,
         {:ok, verifier} <-
           Phoenix.Token.decrypt(Web.Endpoint, @salt, browser_token, max_age: @max_age),
         true <- valid_secret?(verifier),
         %{rows: [[true]]} <-
           Repo.query!(@consume_sql, [hash(state), hash(browser_token)], log: false) do
      {:ok, verifier}
    else
      _ -> {:error, :invalid_attempt}
    end
  end

  @doc "Validate and consume a denied/cancelled attempt without returning its verifier."
  @spec cancel(term(), term()) :: :ok | {:error, :invalid_attempt}
  def cancel(state, browser_token) do
    case consume(state, browser_token) do
      {:ok, _verifier} -> :ok
      {:error, :invalid_attempt} = error -> error
    end
  end

  @doc "Remove at most 1,000 expired rows; also runs when creating an attempt."
  @spec prune_expired() :: non_neg_integer()
  def prune_expired do
    Repo.query!(@prune_sql, [], log: false).num_rows
  end

  defp random_secret, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp valid_secret?(secret) when is_binary(secret) and byte_size(secret) == 43 do
    case Base.url_decode64(secret, padding: false) do
      {:ok, raw} when byte_size(raw) == 32 -> Base.url_encode64(raw, padding: false) == secret
      _ -> false
    end
  end

  defp valid_secret?(_), do: false

  defp hash(value), do: :crypto.hash(:sha256, value)
end
