defmodule Web.HealthControllerTest do
  use Web.ConnCase, async: true

  test "GET /health returns ok and the node's region", %{conn: conn} do
    conn = get(conn, "/health")

    assert %{"status" => "ok", "region" => region} = json_response(conn, 200)
    assert is_binary(region)
  end
end
