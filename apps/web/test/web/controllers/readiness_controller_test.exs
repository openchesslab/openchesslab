defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  alias OpenChessLab.Repo

  test "GET /ready returns ready with all checks green and the digest coverage", %{
    conn: conn
  } do
    body =
      conn
      |> get("/ready")
      |> json_response(200)

    assert body["status"] == "ready"

    assert body["checks"] == %{
             "database" => "ok",
             "horde" => "ok",
             "migrations" => "ok"
           }

    assert is_number(body["digest_coverage"]) or is_nil(body["digest_coverage"])
  end

  test "GET /ready reports migration drift as unavailable", %{conn: conn} do
    [version | _rest] = OpenChessLab.Database.Migrations.expected_versions()

    %{rows: [[applied]]} = Repo.query!("SELECT array_agg(version) FROM schema_migrations")

    Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [version])

    try do
      conn = get(conn, "/ready")
      body = json_response(conn, 503)

      assert body["status"] == "unavailable"
      assert body["checks"]["migrations"] =~ "drift"
    after
      for version <- applied do
        Repo.query!(
          "INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING",
          [version]
        )
      end
    end
  end
end
