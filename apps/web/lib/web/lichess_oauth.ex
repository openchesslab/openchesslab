defmodule Web.LichessOAuth do
  @moduledoc """
  Verify a Lichess authorization code after consuming its browser-bound attempt.

  `config` must contain the trusted client ID and exact redirect URI used when
  authorization started, never values from callback parameters. The browser
  token must come only from the initiating browser's protected cookie. Provider
  denial should instead use `LichessOAuthAttempts.cancel/2`.

  Only the provider and verified opaque `id` are returned, for subsequent HMAC
  account resolution. The rest of the profile and the access token are discarded.
  Once a usable token is received, revocation is attempted even if account
  verification fails. Success requires confirmed revocation; network failures
  may leave a provider grant alive, but it is never persisted or logged here.

  This does not create users, link accounts, establish sessions or expose routes.
  The optional request function is a trusted HTTP test seam, not client input.
  """

  alias Web.LichessOAuthAttempts

  @token_url ~c"https://lichess.org/api/token"
  @account_url ~c"https://lichess.org/api/account"
  @headers [{~c"accept", ~c"application/json"}]
  @max_body_size 65_536

  @type config :: %{client_id: String.t(), redirect_uri: String.t()}
  @type identity :: %{provider: String.t(), subject: String.t()}
  @type error ::
          :invalid_attempt
          | :invalid_code
          | :invalid_configuration
          | :token_exchange_failed
          | :invalid_token_response
          | :account_verification_failed
          | :revocation_failed

  @spec verify_callback(term(), term(), term(), config(), function()) ::
          {:ok, identity()} | {:error, error()}
  def verify_callback(state, browser_token, code, config, request \\ &:httpc.request/4) do
    with {:ok, verifier} <- LichessOAuthAttempts.consume(state, browser_token),
         :ok <- validate_config(config),
         :ok <- validate_code(code) do
      body =
        URI.encode_query(%{
          "grant_type" => "authorization_code",
          "client_id" => config.client_id,
          "redirect_uri" => config.redirect_uri,
          "code" => code,
          "code_verifier" => verifier
        })

      http_options = [
        ssl: :httpc.ssl_verify_host_options(true),
        connect_timeout: 5_000,
        timeout: 10_000,
        autoredirect: false,
        autoretry: 0
      ]

      with {:ok, response} <-
             json_request(
               request,
               :post,
               {@token_url, @headers, ~c"application/x-www-form-urlencoded", body},
               http_options,
               :token_exchange_failed
             ),
           {:ok, token} <- access_token(response) do
        result = verify_account(response, token, request, http_options)
        revoked = revoke(token, request, http_options)

        case {result, revoked} do
          {{:ok, identity}, :ok} -> {:ok, identity}
          {{:ok, _identity}, :error} -> {:error, :revocation_failed}
          {{:error, _} = error, _} -> error
        end
      end
    end
  end

  defp verify_account(%{"token_type" => type, "expires_in" => expiry}, token, request, options)
       when is_binary(type) and is_integer(expiry) and expiry > 0 do
    if String.downcase(type) == "bearer" do
      with {:ok, profile} <-
             json_request(
               request,
               :get,
               {@account_url, bearer_headers(token)},
               options,
               :account_verification_failed
             ) do
        case profile do
          %{"id" => id} when is_binary(id) and byte_size(id) in 1..512 ->
            if String.valid?(id) and String.trim(id) != "" do
              # Do not retain the complete profile JSON through a sub-binary.
              {:ok, %{provider: "lichess", subject: :binary.copy(id)}}
            else
              {:error, :account_verification_failed}
            end

          _ ->
            {:error, :account_verification_failed}
        end
      end
    else
      {:error, :invalid_token_response}
    end
  end

  defp verify_account(_, _, _, _), do: {:error, :invalid_token_response}

  defp access_token(%{"access_token" => token}) do
    if valid_oauth_string?(token), do: {:ok, token}, else: {:error, :invalid_token_response}
  end

  defp access_token(_), do: {:error, :invalid_token_response}

  defp revoke(token, request, options) do
    case send_request(request, :delete, {@token_url, bearer_headers(token)}, options) do
      {:ok, {{_version, 204, _reason}, _headers, _body}} -> :ok
      _ -> :error
    end
  end

  defp bearer_headers(token),
    do: [{~c"authorization", String.to_charlist("Bearer " <> token)} | @headers]

  defp json_request(request, method, payload, options, error) do
    with {:ok, {{_version, 200, _reason}, headers, body}} <-
           send_request(request, method, payload, options),
         true <- is_binary(body) and byte_size(body) <= @max_body_size,
         true <- json_content_type?(headers),
         {:ok, data} when is_map(data) <- Jason.decode(body) do
      {:ok, data}
    else
      _ -> {:error, error}
    end
  end

  defp send_request(request, method, payload, options) do
    request.(method, payload, options,
      body_format: :binary,
      max_body_size: @max_body_size,
      max_header_size: 8192
    )
  catch
    :exit, _reason -> {:error, :transport_unavailable}
  end

  defp json_content_type?(headers) do
    Enum.any?(headers, fn {name, value} ->
      String.downcase(to_string(name)) == "content-type" and
        value
        |> to_string()
        |> String.split(";", parts: 2)
        |> hd()
        |> String.trim()
        |> String.downcase() == "application/json"
    end)
  end

  defp validate_code(code) do
    if valid_oauth_string?(code), do: :ok, else: {:error, :invalid_code}
  end

  # Lichess documents this alphabet and asks clients to support at least 512 bytes.
  defp valid_oauth_string?(value) when is_binary(value) and byte_size(value) in 1..4096,
    do: Regex.match?(~r/\A[A-Za-z0-9_]+\z/, value)

  defp valid_oauth_string?(_), do: false

  @doc "Validate trusted OAuth configuration without making a provider request."
  @spec validate_config(term()) :: :ok | {:error, :invalid_configuration}
  def validate_config(%{client_id: client_id, redirect_uri: redirect_uri})
      when is_binary(client_id) and byte_size(client_id) in 1..256 and
             is_binary(redirect_uri) and byte_size(redirect_uri) in 1..2048 do
    with true <- String.valid?(client_id) and String.trim(client_id) != "",
         {:ok, uri} <- URI.new(redirect_uri),
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) and is_nil(uri.fragment),
         true <-
           uri.scheme == "https" or
             (uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1", "::1"]) do
      :ok
    else
      _ -> {:error, :invalid_configuration}
    end
  end

  def validate_config(_), do: {:error, :invalid_configuration}
end
