defmodule Web.HomeLiveTest do
  use Web.ConnCase, async: false

  test "renders the room entry screen with the request locale", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?locale=nl")

    assert render(view) =~ "Kamer aanmaken"
    assert render(view) =~ "Kamer binnengaan"
  end

  test "joining an unknown room displays a useful error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    html = render_submit(view, "join-room", %{"code" => "XXXXXX"})

    assert html =~ "No room with that code"
  end

  test "creating a room navigates to its collaborative workspace", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: path}}} = render_submit(view, "create-room", %{})
    assert path =~ ~r|^/rooms/[A-HJ-NP-Z2-9]{6}$|
  end
end
