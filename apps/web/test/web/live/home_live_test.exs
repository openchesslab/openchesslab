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

  test "separate room creation requests produce distinct durable rooms", %{conn: conn} do
    {:ok, first, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: first_path}}} =
             render_submit(first, "create-room", %{})

    {:ok, second, _html} = live(build_conn(), "/")

    assert {:error, {:live_redirect, %{to: second_path}}} =
             render_submit(second, "create-room", %{})

    refute first_path == second_path

    first_code = String.replace_prefix(first_path, "/rooms/", "")
    second_code = String.replace_prefix(second_path, "/rooms/", "")

    on_exit(fn ->
      Analysis.Rooms.stop_room(first_code)
      Analysis.Rooms.stop_room(second_code)
    end)

    assert {:ok, _room} = Analysis.Rooms.get(first_code)
    assert {:ok, _room} = Analysis.Rooms.get(second_code)
  end

  test "creating a room navigates to its collaborative workspace", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert {:error, {:live_redirect, %{to: path}}} = render_submit(view, "create-room", %{})
    assert path =~ ~r|^/rooms/[A-HJ-NP-Z2-9]{6}$|
  end
end
