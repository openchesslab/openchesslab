defmodule Web.GettextTest do
  use ExUnit.Case, async: true

  test "translates web text to Dutch" do
    translation =
      Gettext.with_locale(Web.Gettext, "nl", fn ->
        Gettext.dgettext(
          Web.Gettext,
          "default",
          "Selected analysis"
        )
      end)

    assert translation == "Geselecteerde analyse"
  end

  test "keeps English source text in English" do
    translation =
      Gettext.with_locale(Web.Gettext, "en", fn ->
        Gettext.dgettext(
          Web.Gettext,
          "default",
          "Selected analysis"
        )
      end)

    assert translation == "Selected analysis"
  end
end
