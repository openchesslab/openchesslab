defmodule Web.Plugs.CanonicalHost do
  @moduledoc false

  import Plug.Conn

  @canonical_host "openchesslab.com"
  @www_host "www.openchesslab.com"

  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(
        %Plug.Conn{
          host: @www_host
        } = conn,
        _opts
      ) do
    location =
      "https://#{@canonical_host}" <>
        conn.request_path <>
        query_suffix(conn.query_string)

    conn
    |> put_resp_header(
      "location",
      location
    )
    |> send_resp(
      308,
      ""
    )
    |> halt()
  end

  def call(conn, _opts) do
    conn
  end

  defp query_suffix("") do
    ""
  end

  defp query_suffix(query_string) do
    "?#{query_string}"
  end
end
