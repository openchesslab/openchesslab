defmodule Web.LocalizationTest do
  use Web.ConnCase, async: true

  test "uses English as the application default locale" do
    assert Localize.default_locale().cldr_locale_id == :en
  end

  test "supports English and Dutch" do
    assert MapSet.new(Localize.supported_locales()) ==
             MapSet.new([:en, :nl])
  end

  test "the LiveView root language follows ?locale=", %{conn: conn} do
    assert conn
           |> get("/?locale=nl")
           |> html_response(200)
           |> String.contains?(~s(lang="nl"))
  end

  test "Dutch UI copy is rendered by the LiveView", %{conn: conn} do
    assert conn
           |> get("/?locale=nl")
           |> html_response(200)
           |> String.contains?("Kamer aanmaken")
  end
end
