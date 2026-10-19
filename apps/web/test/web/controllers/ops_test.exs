defmodule Web.OpsTest do
  use Web.ConnCase, async: false

  defp with_ops_credentials(conn) do
    put_req_header(conn, "authorization", "Basic " <> Base.encode64("ops:ops-local-dev"))
  end

  test "ops surfaces reject unauthenticated requests" do
    conn = get(build_conn(), "/ops/status.json")
    assert response(conn, 401) =~ "Unauthorized"

    conn = get(build_conn(), "/ops/dashboard")
    assert response(conn, 401) =~ "Unauthorized"
  end

  test "status.json reports the honest corpus and digest numbers" do
    body =
      build_conn()
      |> with_ops_credentials()
      |> get("/ops/status.json")
      |> json_response(200)

    assert is_integer(body["corpus"]["positions"])
    assert is_integer(body["corpus"]["records"])
    assert is_integer(body["features"]["atoms"])
    assert is_integer(body["features"]["digests"])
    assert is_number(body["features"]["digest_coverage"])
    assert is_integer(body["rooms"]["active"])
    assert is_binary(body["node"]["region"])
  end

  test "the dashboard loads with credentials" do
    conn =
      build_conn()
      |> with_ops_credentials()
      |> get("/ops/dashboard")

    assert redirected_to(conn, 302) == "/ops/dashboard/home"

    conn =
      build_conn()
      |> with_ops_credentials()
      |> get("/ops/dashboard/home")

    assert html_response(conn, 200) =~ "LiveDashboard"
  end
end
