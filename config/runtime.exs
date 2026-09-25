import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/web start
#
if System.get_env("PHX_SERVER") do
  config :web, Web.Endpoint, server: true
end

config :web, Web.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :web, Web.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/web/router\.ex$",
        ~r"lib/web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :web, Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  if System.get_env("DNS_CLUSTER_QUERY") do
    unless System.get_env("RELEASE_NODE") do
      raise """
      RELEASE_NODE must be configured when DNS_CLUSTER_QUERY is enabled
      """
    end

    unless System.get_env("RELEASE_COOKIE") do
      raise """
      RELEASE_COOKIE must be configured when DNS_CLUSTER_QUERY is enabled
      """
    end
  end
end

config :analysis,
  dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY") || :ignore

position_store_owner =
  case System.get_env("POSITION_STORE_OWNER") do
    nil ->
      true

    "true" ->
      true

    "false" ->
      false

    value ->
      raise """
      POSITION_STORE_OWNER must be true or false, got: #{inspect(value)}
      """
  end

config :analysis, Analysis.PositionStoreOwner, owner: position_store_owner

game_store_owner =
  case System.get_env("GAME_STORE_OWNER") do
    nil ->
      true

    "true" ->
      true

    "false" ->
      false

    value ->
      raise """
      GAME_STORE_OWNER must be true or false, got: #{inspect(value)}
      """
  end

config :analysis, Analysis.GameStoreOwner, owner: game_store_owner

position_store_options =
  case System.get_env("POSITION_STORE_DIRECTORY") do
    nil ->
      []

    directory ->
      [
        directory: directory,
        records_per_segment:
          System.get_env(
            "POSITION_STORE_RECORDS_PER_SEGMENT",
            "1000000"
          )
          |> String.to_integer(),
        exact_bucket_count:
          System.get_env(
            "POSITION_STORE_EXACT_BUCKET_COUNT",
            "1048576"
          )
          |> String.to_integer(),
        property_bucket_count:
          System.get_env(
            "POSITION_STORE_PROPERTY_BUCKET_COUNT",
            "65536"
          )
          |> String.to_integer()
      ]
  end

config :analysis,
       Analysis.PositionStore,
       position_store_options
