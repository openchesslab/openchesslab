import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define any
# compile-time configuration in here, as it won't be applied.

# Stable identity key, independent of SECRET_KEY_BASE. Never generate at boot.
account_key =
  case System.get_env("ACCOUNT_SUBJECT_HMAC_KEY") do
    nil ->
      nil

    encoded ->
      case Base.decode64(encoded) do
        {:ok, key} when byte_size(key) >= 32 -> key
        _ -> raise "ACCOUNT_SUBJECT_HMAC_KEY must be standard Base64 encoding at least 32 bytes"
      end
  end

if account_key do
  config :analysis, account_subject_hmac_key: account_key
end

# Provider-grant encryption key, independent of the identity key. Never
# generate at boot: encrypted tokens must stay readable across releases.
grant_key =
  case System.get_env("PROVIDER_GRANT_KEY") do
    nil ->
      nil

    encoded ->
      case Base.decode64(encoded) do
        {:ok, key} when byte_size(key) >= 32 -> key
        _ -> raise "PROVIDER_GRANT_KEY must be standard Base64 encoding at least 32 bytes"
      end
  end

if grant_key do
  config :analysis, provider_grant_key: grant_key
end

lichess_config = %{
  client_id: System.get_env("LICHESS_CLIENT_ID"),
  redirect_uri: System.get_env("LICHESS_REDIRECT_URI")
}

if lichess_config.client_id != nil or lichess_config.redirect_uri != nil do
  if Web.LichessOAuth.validate_config(lichess_config) != :ok do
    raise "LICHESS_CLIENT_ID and LICHESS_REDIRECT_URI must contain valid OAuth configuration"
  end

  if config_env() == :prod do
    if is_nil(account_key) do
      raise "ACCOUNT_SUBJECT_HMAC_KEY is required for production Lichess authentication"
    end

    if URI.parse(lichess_config.redirect_uri).scheme != "https" do
      raise "LICHESS_REDIRECT_URI must use HTTPS in production"
    end
  end

  config :web, :lichess_oauth, lichess_config
else
  config :web, :lichess_oauth, nil
end

google_config = %{
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")
}

if Enum.any?(Map.values(google_config), &(not is_nil(&1))) do
  if Web.GoogleOAuth.validate_config(google_config) != :ok do
    raise "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET and GOOGLE_REDIRECT_URI must contain valid OAuth configuration"
  end

  if config_env() == :prod do
    if is_nil(account_key),
      do: raise("ACCOUNT_SUBJECT_HMAC_KEY is required for production Google authentication")

    if URI.parse(google_config.redirect_uri).scheme != "https",
      do: raise("GOOGLE_REDIRECT_URI must use HTTPS in production")
  end

  config :web, :google_oauth, google_config
else
  config :web, :google_oauth, nil
end

if System.get_env("PHX_SERVER") do
  config :web, Web.Endpoint, server: true
end

config :web, Web.Endpoint,
  http: [
    port:
      System.get_env(
        "PORT",
        "4000"
      )
      |> String.to_integer()
  ]

if config_env() == :dev do
  config :web, Web.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        ~r"lib/web/router\.ex$",
        ~r"lib/web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      PostgreSQL is authoritative storage and must be configured in production.
      """

  database_url =
    String.replace(
      database_url,
      "@pgbouncer.",
      "@direct.",
      global: false
    )

  socket_options =
    if System.get_env("ECTO_IPV6") in [
         "true",
         "1"
       ] do
      [:inet6]
    else
      []
    end

  pool_size =
    System.get_env(
      "POOL_SIZE",
      "10"
    )
    |> String.to_integer()

  host =
    System.get_env("PHX_HOST") ||
      "example.com"

  config :database, OpenChessLab.Repo,
    url: database_url,
    pool_size: pool_size,
    socket_options: socket_options

  config :web, Web.Endpoint,
    url: [
      host: host,
      port: 443,
      scheme: "https"
    ],
    http: [
      ip: {
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
      }
    ],
    secret_key_base: secret_key_base

  if System.get_env("DNS_CLUSTER_QUERY") do
    if !System.get_env("RELEASE_NODE") do
      raise """
      RELEASE_NODE must be configured when DNS_CLUSTER_QUERY is enabled
      """
    end

    if !System.get_env("RELEASE_COOKIE") do
      raise """
      RELEASE_COOKIE must be configured when DNS_CLUSTER_QUERY is enabled
      """
    end
  end
end

config :analysis,
  dns_cluster_query:
    System.get_env("DNS_CLUSTER_QUERY") ||
      :ignore
