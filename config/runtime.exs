import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define any
# compile-time configuration in here, as it won't be applied.

if System.get_env("PHX_SERVER") do
  config :web, Web.Endpoint, server: true
end

config :web, Web.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

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
    pool_size: pool_size

  config :web, Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
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
