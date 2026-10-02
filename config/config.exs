import Config

config :analysis,
  position_repository: Analysis.PositionRepository.Postgres,
  game_repository: Analysis.GameRepository.Postgres,
  game_record_repository: Analysis.GameRecordRepository.Postgres

config :database, OpenChessLab.Repo,
  migration_primary_key: [
    name: :id,
    type: :identity
  ],
  migration_foreign_key: [
    type: :bigint
  ]

config :database,
  ecto_repos: [OpenChessLab.Repo]

config :esbuild,
  version: "0.25.4",
  web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :localize,
  default_locale: :en,
  supported_locales: [:en, :nl],
  otp_app: :web

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{"application/x-chess-pgn" => ["pgn"]}

config :phoenix, :json_library, Jason

config :phoenix_live_view,
  root_tag_attribute: "phx-r",
  colocated_assets: [disable_symlink_warning: true]

config :tailwind,
  version: "4.3.0",
  web: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/app.css),
    cd: Path.expand("../apps/web", __DIR__)
  ]

config :web, Web.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: Web.ErrorHTML, json: Web.ErrorJSON],
    layout: false
  ],
  pubsub_server: Web.PubSub,
  live_view: [signing_salt: "3afc4cc97cfdd88a2e57b7b628e59b47"]

import_config "#{config_env()}.exs"
