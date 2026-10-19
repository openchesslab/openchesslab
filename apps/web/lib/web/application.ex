defmodule Web.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    sync_children =
      if Application.get_env(:web, :lichess_sync_worker, true),
        do: [Web.LichessSync.Worker],
        else: []

    # The Prometheus scrape endpoint listens on a separate port that only
    # Fly's internal scraper reaches; the public service stays on 8080.
    metrics_children =
      if Application.get_env(:web, :prometheus_listener, true) do
        [
          {TelemetryMetricsPrometheus,
           metrics: Web.Telemetry.metrics(),
           protocol: :http,
           name: :web_metrics,
           port: 9091,
           plug_cowboy_opts: [ip: {0, 0, 0, 0}]}
        ]
      else
        []
      end

    children =
      [
        {Phoenix.PubSub, name: Web.PubSub},
        Web.Presence,
        Web.Telemetry
      ] ++ sync_children ++ metrics_children ++ [Web.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
