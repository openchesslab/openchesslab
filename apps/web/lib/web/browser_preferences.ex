defmodule Web.BrowserPreferences do
  @moduledoc "Read presentation-only cookies before rendering a browser request."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    theme = theme_from_session(%{"ui_theme" => conn.cookies["_ocl_theme"]})

    conn =
      conn
      |> assign(:theme, theme)
      |> put_session(:ui_theme, theme)

    case conn.cookies["_ocl_locale"] do
      locale when locale in ["en", "nl"] ->
        put_session(conn, Localize.Plug.PutLocale.session_key(), locale)

      _ ->
        conn
    end
  end

  def theme_from_session(%{"ui_theme" => theme}) when theme in ["system", "light", "dark"],
    do: theme

  def theme_from_session(_session), do: "system"
end
