defmodule Web.GamesLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Games

  test "renders stored games", %{conn: conn} do
    game_id =
      "game-#{System.unique_integer([:positive])}"

    assert {:ok, _game, 1} =
             Games.create(game_id)

    {:ok, view, _html} =
      live(conn, "/games")

    assert has_element?(view, "h1", "Games")

    assert has_element?(
             view,
             "#game-#{game_id} .game-id",
             game_id
           )

    assert has_element?(
             view,
             "#game-#{game_id} .game-revision",
             "Revision 1"
           )
  end

  test "renders the games page in Dutch", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/games?locale=nl")

    assert has_element?(view, "h1", "Partijen")
  end
end
