defmodule Web.PageLiveTest do
  use Web.ConnCase, async: true

  test "renders the homepage in English by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "OpenChessLab"

    assert html =~
             "A collaborative chess analysis platform built with Phoenix LiveView."
  end

  test "renders the homepage in Dutch", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/?locale=nl")

    assert html =~ "OpenChessLab"

    assert html =~
             "Een samenwerkingsplatform voor schaakanalyse, gebouwd met Phoenix LiveView."

    refute html =~
             "A collaborative chess analysis platform built with Phoenix LiveView."
  end
end
