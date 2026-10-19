defmodule Web.Router do
  use Web, :router
  import Web.UserAuth, only: [require_authenticated_user: 2]
  import Phoenix.LiveDashboard.Router

  pipeline :authenticated do
    plug(:require_authenticated_user)
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(Web.SessionName)
    plug(Web.UserAuth)
    plug(Web.BrowserPreferences)

    plug(Localize.Plug.PutLocale,
      from: [:query, :session, :accept_language],
      default: :en
    )

    plug(Localize.Plug.PutSession)

    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Web.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:put_secure_browser_headers)
  end

  scope "/", Web do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/ready", ReadinessController, :show)
  end

  # The home and room workspace are server-rendered LiveViews. Analysis
  # operations call their domain APIs directly from the web boundary.
  scope "/", Web do
    pipe_through(:browser)

    post("/auth/logout", SessionController, :delete)
    post("/auth/:provider", OAuthController, :create)
    get("/auth/:provider/callback", OAuthController, :callback)

    live_session :public, on_mount: {Web.UserAuth, :default} do
      live("/", HomeLive, :index)
      live("/rooms/:code", RoomLive, :show)
    end

    get("/rooms/:code/join/:token", RoomInviteController, :join)
  end

  # Ops surface behind basic auth (OPS_USER/OPS_PASSWORD, Fly secrets):
  # the LiveDashboard and a small honest status snapshot.
  scope "/ops", Web do
    pipe_through([:browser, Web.OpsAuth])

    get("/status.json", OpsStatusController, :show)

    live_dashboard("/dashboard",
      metrics: false,
      ecto_repos: [OpenChessLab.Repo],
      allow_destructive_actions: false
    )
  end

  # Other scopes may use custom stacks.
  scope "/", Web do
    pipe_through([:browser, :authenticated])

    post("/account/delete", AccountController, :delete)
    post("/auth/:provider/link", OAuthController, :link)
  end

  # scope "/api", Web do
  #   pipe_through :api
  # end
end
