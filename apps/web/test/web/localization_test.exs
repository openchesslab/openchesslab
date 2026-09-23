defmodule Web.LocalizationTest do
  use ExUnit.Case, async: true

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
end
