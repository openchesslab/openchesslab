defmodule Analysis.LibraryImportTest do
  use ExUnit.Case, async: false

  alias Analysis.{LibraryImport, UserLibrary, Users}

  setup do
    {:ok, user} = Users.create()
    on_exit(fn -> Users.delete(user.id) end)
    %{user: user}
  end

  test "imports games as titled library entries", %{user: user} do
    result =
      LibraryImport.import_games(user.id, [
        %{pgn: "[Event \"A\"]\n\n1. e4 e5 2. Nf3 Nc6 *", title: "Alpha – Beta 1-0 (2026)"},
        %{pgn: "[Event \"B\"]\n\n1. d4 d5 *", title: "Gamma – Delta ½-½ (2026)"}
      ])

    assert result.skipped == 0
    assert length(result.imported) == 2

    page = UserLibrary.page(user.id)
    assert length(page.entries) == 2

    assert Enum.map(page.entries, & &1.title) |> Enum.sort() ==
             ["Alpha – Beta 1-0 (2026)", "Gamma – Delta ½-½ (2026)"]

    # Every entry opens as a real analysis.
    assert Enum.all?(page.entries, &match?(%{game_record_id: record} when is_binary(record), &1))
  end

  test "bad games are counted as skipped, good ones still land", %{user: user} do
    result =
      LibraryImport.import_games(user.id, [
        %{pgn: "[Event \"ok\"]\n\n1. e4 e5 *", title: "Ok"},
        %{pgn: "[Event \"bad\"]\n\n1. e4 e9 *", title: "Bad"}
      ])

    assert result.skipped == 1
    assert length(result.imported) == 1
    assert length(UserLibrary.page(user.id).entries) == 1
  end
end
