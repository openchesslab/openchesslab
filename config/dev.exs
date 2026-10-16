import Config

database_url =
  System.get_env(
    "DATABASE_URL",
    "ecto://openchesslab:openchesslab@localhost/openchesslab_dev"
  )

# For development, we disable any cache and enable
# debugging and code reloading.
#

# Local-only development key. Never reuse in production.
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :analysis, account_subject_hmac_key: String.duplicate("dev-only-hmac-key-", 3)
config :analysis, provider_grant_key: String.duplicate("dev-only-grant-key-", 3)

config :database, OpenChessLab.Repo, url: database_url

# Do not include metadata nor timestamps in development logs
# Binding to loopback ipv4 address prevents access from other machines.
# Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
# Compile the LiveView hooks and Tailwind stylesheet while developing.
config :logger, :default_formatter, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation
# Include debug annotations and locations in rendered markup.
# Set a higher stacktrace during development. Avoid configuring such
# Changing this configuration will require mix clean and a full recompile.
config :phoenix, :plug_init_mode, :runtime
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

config :web, Web.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "c2b79f93272f86409bd47252aacb42192a1d1bd8c56e39e0845fdce975de7169702ca7bd7d14387795fb14cb3f3f85bdcacbcfed6179a89e09d1de7f4a267513",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:web, ~w(--watch)]}
  ],

  # Reload on changes to the web hooks, Tailwind stylesheet, or static
  # assets. Elixir source recompilation remains owned by CodeReloader.
  live_reload: [
    patterns: [
      ~r"apps/web/assets/(css|js)/.*",
      ~r"priv/static/.*"
    ]
  ]
