defmodule Web.TelemetryTest do
  use ExUnit.Case, async: false

  test "the metrics definitions compile into a working Prometheus core" do
    metrics = Web.Telemetry.metrics()

    assert metrics != []

    metric_types = [
      Telemetry.Metrics.Counter,
      Telemetry.Metrics.Distribution,
      Telemetry.Metrics.LastValue,
      Telemetry.Metrics.Sum,
      Telemetry.Metrics.Summary
    ]

    assert Enum.all?(metrics, &(&1.__struct__ in metric_types))

    {:ok, _pid} =
      TelemetryMetricsPrometheus.Core.start_link(
        metrics: metrics,
        name: :web_telemetry_test_metrics,
        start_async: false
      )

    # The event handler records synchronously; fire controlled events.
    OpenChessLab.Repo.query!("SELECT 1")

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: System.convert_time_unit(5, :millisecond, :native)},
      %{conn: %Plug.Conn{status: 200}}
    )

    text = TelemetryMetricsPrometheus.Core.scrape(:web_telemetry_test_metrics)

    assert text =~ "open_chess_lab_repo_query_total_time"
    assert text =~ ~s(phoenix_endpoint_stop_duration_bucket{status_int="200")
  end
end
