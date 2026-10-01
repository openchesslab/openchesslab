import Config

config :phoenix_live_view,
  root_tag_attribute: "phx-r",
  colocated_assets: [disable_symlink_warning: true]

config :web, Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: Web.ErrorHTML, json: Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Web.PubSub,
  live_view: [signing_salt: "3afc4cc97cfdd88a2e57b7b628e59b47"]

config :esbuild,
  version: "0.25.4",
  web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.3.0",
  web: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/app.css),
    cd: Path.expand("../apps/web", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :localize,
  default_locale: :en,
  supported_locales: [:en, :nl],
  otp_app: :web

config :mime, :types, %{"application/x-chess-pgn" => ["pgn"]}

config :database,
  ecto_repos: [OpenChessLab.Repo]

config :database, OpenChessLab.Repo,
  migration_primary_key: [
    name: :id,
    type: :identity
  ],
  migration_foreign_key: [
    type: :bigint
  ]

config :analysis,
  position_repository: Analysis.PositionRepository.Postgres,
  game_repository: Analysis.GameRepository.Postgres

import_config "#{config_env()}.exs"
