defmodule Web.PageLiveTest do
  use Web.ConnCase, async: true

  test "renders the default LiveView page" do
    {:ok, _live, html} = live(conn(), "/")

    assert html =~ "OpenChessLab"
    assert html =~ "collaborative chess analysis platform"
  end
end
