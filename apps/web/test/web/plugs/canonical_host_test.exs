defmodule Web.Plugs.CanonicalHostTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Web.Plugs.CanonicalHost

  test "redirects www to the canonical host while preserving path and query string" do
    conn =
      :get
      |> conn("https://www.openchesslab.com/rooms/ABC123?locale=nl")
      |> CanonicalHost.call([])

    assert conn.status ==
             308

    assert get_resp_header(
             conn,
             "location"
           ) ==
             [
               "https://openchesslab.com/rooms/ABC123?locale=nl"
             ]

    assert conn.halted
  end

  test "redirects the www root to the canonical root" do
    conn =
      :get
      |> conn("https://www.openchesslab.com/")
      |> CanonicalHost.call([])

    assert conn.status ==
             308

    assert get_resp_header(
             conn,
             "location"
           ) ==
             [
               "https://openchesslab.com/"
             ]

    assert conn.halted
  end

  test "does not redirect the canonical host" do
    conn =
      :get
      |> conn("https://openchesslab.com/rooms/ABC123")
      |> CanonicalHost.call([])

    assert conn.status ==
             nil

    refute conn.halted
  end

  test "does not redirect the Fly host" do
    conn =
      :get
      |> conn("https://openchesslab.fly.dev/health")
      |> CanonicalHost.call([])

    assert conn.status ==
             nil

    refute conn.halted
  end
end
