defmodule Web.ReadinessController do
  use Web, :controller

  alias OpenChessLab.Database.Migrations
  alias OpenChessLab.Repo

  # Readiness means the database answers, its migrations match this release
  # and the room registry is alive. The digest coverage rides along as
  # information; progress (a stalled backfill) is a monitoring concern.
  def show(conn, _params) do
    checks = %{
      database: database_check(),
      migrations: migrations_check(),
      horde: horde_check()
    }

    if Enum.all?(checks, fn {_check, status} -> status == "ok" end) do
      json(conn, %{status: "ready", checks: checks, digest_coverage: digest_coverage()})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "unavailable", checks: checks})
    end
  end

  defp database_check do
    if Repo.ready?(), do: "ok", else: "unavailable"
  end

  defp migrations_check do
    case Migrations.missing() do
      [] -> "ok"
      missing -> "drift:#{Enum.join(missing, ",")}"
    end
  end

  defp horde_check do
    Horde.Registry.count(Analysis.RoomRegistry)
    "ok"
  rescue
    _ -> "unavailable"
  catch
    _, _ -> "unavailable"
  end

  defp digest_coverage do
    case Repo.query(
           """
           SELECT
             (SELECT reltuples::bigint FROM pg_class WHERE relname = 'position_digests'),
             (SELECT reltuples::bigint FROM pg_class WHERE relname = 'positions')
           """,
           []
         ) do
      {:ok, %{rows: [[digests, positions]]}} when positions > 0 ->
        Float.round(digests / positions, 3)

      _ ->
        nil
    end
  end
end
