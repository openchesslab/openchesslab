defmodule Web.Telemetry do
  @moduledoc """
  Metrics for the Prometheus scrape endpoint: VM health, Phoenix and
  LiveView latency, and repo query time. Tag cardinality stays bounded
  (routes, LiveView events, table sources) — never usernames or other PII.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Database stats we cannot get from Fly's managed Prometheus (the MPG
  # exports no pg_ series), measured ourselves through the Repo.
  @db_stats_sql """
  SELECT
    pg_database_size(current_database()),
    (SELECT count(*) FROM pg_stat_activity),
    blks_hit,
    blks_read
  FROM pg_stat_database
  WHERE datname = current_database()
  """

  def db_stats do
    %{rows: [[size_bytes, connections, blks_hit, blks_read]]} =
      OpenChessLab.Repo.query!(@db_stats_sql, [], log: false)

    :telemetry.execute(
      [:openchesslab, :db, :stats],
      %{
        size_bytes: size_bytes,
        connections: connections,
        blks_hit: blks_hit,
        blks_read: blks_read
      },
      %{}
    )
  end

  @latency_buckets [5, 10, 25, 50, 100, 250, 500, 1_000, 5_000]

  def metrics do
    [
      # VM
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),
      last_value("openchesslab.db.stats.size_bytes", unit: :byte),
      last_value("openchesslab.db.stats.connections"),
      sum("openchesslab.db.stats.blks_hit", description: "PG blocks read from cache"),
      sum("openchesslab.db.stats.blks_read", description: "PG blocks read from disk"),

      # Phoenix
      distribution(
        "phoenix.endpoint.stop.duration",
        description: "Endpoint request duration",
        unit: {:native, :millisecond},
        tags: [:status_int],
        tag_values: fn %{conn: conn} -> %{status_int: conn.status} end,
        reporter_options: [buckets: @latency_buckets]
      ),
      distribution(
        "phoenix.router_dispatch.stop.duration",
        description: "Router dispatch duration per route",
        unit: {:native, :millisecond},
        tags: [:route],
        reporter_options: [buckets: @latency_buckets]
      ),

      # LiveView
      distribution(
        "phoenix.live_view.mount.stop.duration",
        description: "LiveView mount duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @latency_buckets]
      ),
      distribution(
        "phoenix.live_view.handle_event.stop.duration",
        description: "LiveView event handling duration per event",
        unit: {:native, :millisecond},
        tags: [:event],
        reporter_options: [buckets: @latency_buckets]
      ),

      # Repo (raw SQL has no schema source; hot paths get their own labels
      # in the domain-metrics slice)
      distribution(
        "open_chess_lab.repo.query.total_time",
        description: "Repo query total time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @latency_buckets]
      ),
      distribution(
        "open_chess_lab.repo.query.queue_time",
        description: "Repo queue wait",
        unit: {:native, :millisecond},
        reporter_options: [buckets: @latency_buckets]
      )
    ]
  end

  defp periodic_measurements, do: [{__MODULE__, :db_stats, []}]
end
