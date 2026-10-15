defmodule Web.SessionNameTest do
  use Web.ConnCase, async: false

  test "the first visit assigns a display name that persists for the session", %{conn: conn} do
    conn = get(conn, "/")
    name = get_session(conn, :display_name)
    assert name =~ ~r/^\S+ \S+ \d{2}$/

    # A second request in the same session keeps the name.
    assert conn |> recycle() |> get("/") |> get_session(:display_name) == name
  end
end
