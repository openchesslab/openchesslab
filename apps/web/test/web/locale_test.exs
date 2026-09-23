defmodule Web.LocaleTest do
  use ExUnit.Case, async: true

  alias Web.Locale

  test "uses English as the default locale" do
    assert Locale.default() == "en"
  end

  test "lists the supported locales" do
    assert Locale.supported() == ["en", "nl"]
  end

  test "recognizes supported locales" do
    assert Locale.supported?("en")
    assert Locale.supported?("nl")
  end

  test "rejects unsupported locales" do
    refute Locale.supported?("de")
    refute Locale.supported?("")
    refute Locale.supported?(nil)
    refute Locale.supported?(:nl)
  end

  test "keeps a supported locale unchanged" do
    assert Locale.normalize("en") == "en"
    assert Locale.normalize("nl") == "nl"
  end

  test "normalizes unsupported values to the default locale" do
    assert Locale.normalize("de") == "en"
    assert Locale.normalize("") == "en"
    assert Locale.normalize(nil) == "en"
    assert Locale.normalize(:nl) == "en"
  end
end
