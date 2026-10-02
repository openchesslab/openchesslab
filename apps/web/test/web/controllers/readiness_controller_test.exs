defmodule Web.ReadinessControllerTest do
  use Web.ConnCase, async: false

  test "GET /ready returns ready when PostgreSQL is reachable",
       %{conn: conn} do
    conn =
      get(
        conn,
        "/ready"
      )

    assert json_response(
             conn,
             200
           ) ==
             %{
               "status" => "ready"
             }
  end
end
