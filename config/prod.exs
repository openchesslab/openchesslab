import Config

# Do not print debug messages in production
config :logger, level: :info

# Configure the endpoint to serve compressed/digested static assets.
config :web, Web.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
