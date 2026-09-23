defmodule Web.LocalizationTest do
  use Web.ConnCase, async: true

  test "uses English as the application default locale" do
    assert Localize.default_locale().cldr_locale_id == :en
  end

  test "supports English and Dutch" do
    assert MapSet.new(Localize.supported_locales()) ==
             MapSet.new([:en, :nl])
  end

  test "Gettext knows both application locales" do
    assert MapSet.new(Gettext.known_locales(Web.Gettext)) ==
             MapSet.new(["en", "nl"])
  end

  test "renders English as the document language by default", %{conn: conn} do
    html =
      conn
      |> get("/")
      |> html_response(200)

    assert Floki.attribute(
             Floki.parse_document!(html),
             "html",
             "lang"
           ) == ["en"]
  end

  test "renders the selected locale as the document language", %{conn: conn} do
    html =
      conn
      |> get("/?locale=nl")
      |> html_response(200)

    assert Floki.attribute(
             Floki.parse_document!(html),
             "html",
             "lang"
           ) == ["nl"]
  end
end
