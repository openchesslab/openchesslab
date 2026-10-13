import Config

# Automatically clean up rooms older than 30 days that have no analyses.
config :analysis, :room_pruning_enabled, true
config :analysis, :user_session_pruning_enabled, true

# Do not print debug messages in production
config :logger, level: :info

# Configure the endpoint to serve compressed/digested static assets.
config :web, Web.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
