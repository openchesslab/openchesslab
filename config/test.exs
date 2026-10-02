import Config

database_url =
  System.get_env(
    "DATABASE_URL",
    "ecto://openchesslab:openchesslab@localhost/openchesslab_test"
  )

database_name =
  database_url
  |> URI.parse()
  |> Map.fetch!(:path)

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "7LhKrVhM2mVQ42AiDhJ8dKJVDz41Su8A9d5JcaAn8nXzEJqvbWC0dQY1Hqx7cW0pM1eP44YFudvNoSKbur6ANQvGS7E2nD66gxxU",
  server: false

if database_name != "/openchesslab_test" do
  raise """
  MIX_ENV=test must use the openchesslab_test database.
  Got database path: #{inspect(database_name)}
  """
end

config :database, OpenChessLab.Repo,
  url: database_url,
  pool_size: 10,
  log: false
