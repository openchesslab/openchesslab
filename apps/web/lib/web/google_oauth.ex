defmodule Web.GoogleOAuth do
  @moduledoc """
  Google OpenID Connect confidential-server code exchange, requesting only openid.

  Identity is read ONLY from the direct, certificate/hostname-verified HTTPS
  token response authenticated with our client secret. Per Google's server-flow
  contract this authenticates the ID token's origin without a separate signature
  fetch. This module must never accept a browser-supplied ID token. Claims are
  still checked against our client, nonce and clock; only sub leaves the module.
  Access/ID tokens and profile claims are neither persisted nor logged. No
  offline access or other Google API scope is requested.
  """

  @token_url ~c"https://oauth2.googleapis.com/token"
  @max_body_size 65_536

  def validate_config(%{client_secret: secret} = config)
      when is_binary(secret) and byte_size(secret) in 1..4096 do
    if String.valid?(secret) and String.trim(secret) != "",
      do: Web.LichessOAuth.validate_config(config),
      else: {:error, :invalid_configuration}
  end

  def validate_config(_), do: {:error, :invalid_configuration}

  @doc "Requires an already consumed, validated attempt; request is a trusted test seam."
  def verify_code(code, verifier, nonce, config, request) do
    with :ok <- validate_config(config),
         true <- is_binary(code) and byte_size(code) in 1..4096 and String.valid?(code) do
      body =
        URI.encode_query(%{
          "grant_type" => "authorization_code",
          "client_id" => config.client_id,
          "client_secret" => config.client_secret,
          "redirect_uri" => config.redirect_uri,
          "code" => code,
          "code_verifier" => verifier
        })

      options = [
        ssl: :httpc.ssl_verify_host_options(true),
        connect_timeout: 5_000,
        timeout: 10_000,
        autoredirect: false,
        autoretry: 0
      ]

      with {:ok, {{_, 200, _}, headers, response}} <-
             request.(
               :post,
               {@token_url, [{~c"accept", ~c"application/json"}],
                ~c"application/x-www-form-urlencoded", body},
               options,
               body_format: :binary,
               max_body_size: @max_body_size,
               max_header_size: 8192
             ),
           true <- is_binary(response) and byte_size(response) <= @max_body_size,
           true <- json?(headers),
           {:ok, %{"id_token" => token}} <- Jason.decode(response),
           {:ok, subject} <- direct_response_subject(token, nonce, config.client_id) do
        {:ok, %{provider: "google", subject: :binary.copy(subject)}}
      else
        _ -> {:error, :identity_verification_failed}
      end
    else
      _ -> {:error, :invalid_configuration_or_code}
    end
  catch
    :exit, _ -> {:error, :transport_unavailable}
  end

  defp direct_response_subject(token, nonce, client_id) when is_binary(token) do
    now = System.system_time(:second)

    with [header, payload, signature] when signature != "" <- String.split(token, "."),
         {:ok, header} <- Base.url_decode64(header, padding: false),
         {:ok, %{"alg" => "RS256"}} <- Jason.decode(header),
         {:ok, payload} <- Base.url_decode64(payload, padding: false),
         {:ok,
          %{
            "iss" => issuer,
            "aud" => ^client_id,
            "sub" => sub,
            "exp" => exp,
            "iat" => iat,
            "nonce" => ^nonce
          } = claims} <- Jason.decode(payload),
         true <- issuer in ["https://accounts.google.com", "accounts.google.com"],
         true <- Map.get(claims, "azp", client_id) == client_id,
         true <- is_integer(exp) and exp > now,
         true <- is_integer(iat) and iat <= now + 60 and iat < exp,
         true <- is_binary(sub) and byte_size(sub) in 1..255 and String.trim(sub) != "" do
      {:ok, sub}
    else
      _ -> {:error, :invalid_claims}
    end
  end

  defp direct_response_subject(_, _, _), do: {:error, :invalid_claims}

  defp json?(headers) do
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
end
