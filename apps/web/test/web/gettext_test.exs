defmodule Web.GettextTest do
  use ExUnit.Case, async: true

  test "translates web text to Dutch" do
    assert Gettext.dgettext(
             Web.Gettext,
             "default",
             "Selected game",
             locale: "nl"
           ) == "Geselecteerde partij"
  end

  test "keeps English source text in English" do
    assert Gettext.dgettext(
             Web.Gettext,
             "default",
             "Selected game",
             locale: "en"
           ) == "Selected game"
  end
end
