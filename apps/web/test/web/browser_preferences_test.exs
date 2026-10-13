defmodule Web.BrowserPreferencesTest do
  use Web.ConnCase, async: false

  test "saved preferences are present in the initial HTML and connected mount on both routes" do
    code = "PREF" <> Base.encode16(:crypto.strong_rand_bytes(4))
    {:ok, _} = Analysis.Rooms.start_room(code)
    on_exit(fn -> Analysis.Rooms.stop_room(code) end)

    for path <- ["/", "/rooms/#{code}"] do
      conn =
        build_conn()
        |> put_req_cookie("_ocl_theme", "dark")
        |> put_req_cookie("_ocl_locale", "nl")
        |> put_req_header("accept-language", "en")
        |> get(path)

      html = html_response(conn, 200)
      root = html |> LazyHTML.from_document() |> LazyHTML.query("html")
      assert LazyHTML.attribute(root, "lang") == ["nl"]
      assert LazyHTML.attribute(root, "data-theme") == ["dark"]
      assert html =~ ~s(data-theme="dark")
      assert html =~ "Kamer"
      assert conn.assigns.current_user == nil

      {:ok, view, _} = live(conn)
      assert :sys.get_state(view.pid).socket.assigns.theme == "dark"
      assert :sys.get_state(view.pid).socket.assigns.locale == "nl"
    end
  end

  test "light and system choices also apply to the document before JavaScript runs" do
    for theme <- ["light", "system"] do
      conn = build_conn() |> put_req_cookie("_ocl_theme", theme) |> get("/")
      root = conn |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("html")
      assert LazyHTML.attribute(root, "lang") == ["en"]
      assert LazyHTML.attribute(root, "data-theme") == [theme]
    end
  end

  test "unsupported cookies are ignored and cannot supply identity or HTML" do
    conn =
      build_conn()
      |> put_req_cookie("_ocl_theme", "evil-theme")
      |> put_req_cookie("_ocl_locale", "invalid-locale")
      |> get("/")

    html = html_response(conn, 200)
    root = html |> LazyHTML.from_document() |> LazyHTML.query("html")
    assert LazyHTML.attribute(root, "lang") == ["en"]
    assert LazyHTML.attribute(root, "data-theme") == ["system"]
    refute html =~ "evil-theme"
    refute html =~ "invalid-locale"
    assert conn.assigns.current_user == nil
  end

  test "an explicit locale query still takes precedence over the saved cookie" do
    conn = build_conn() |> put_req_cookie("_ocl_locale", "nl") |> get("/?locale=en")
    root = conn |> html_response(200) |> LazyHTML.from_document() |> LazyHTML.query("html")
    assert LazyHTML.attribute(root, "lang") == ["en"]
  end
end
