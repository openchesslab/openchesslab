defmodule Web.Router do
  use Web, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)

    plug(Localize.Plug.PutLocale,
      from: [:query, :session, :accept_language],
      default: :en,
      gettext: Web.Gettext
    )

    plug(Localize.Plug.PutSession)

    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Web.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", Web do
    pipe_through(:api)

    get("/health", HealthController, :show)
  end

  scope "/", Web do
    pipe_through(:browser)

    live_session :default,
      on_mount: [{Web.LocaleLive, :default}] do
      live("/", PageLive, :index)
      live("/games", GamesLive, :index)
      live("/rooms/:room_id", RoomLive, :show)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", Web do
  #   pipe_through :api
  # end
end
