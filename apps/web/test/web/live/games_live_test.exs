defmodule Web.GamesLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Games
  alias Analysis.Rooms

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

  test "opens a stored game in a room", %{conn: conn} do
    game_id =
      "game-#{System.unique_integer([:positive])}"

    room_id =
      "room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Rooms.stop_room(room_id)
    end)

    assert {:ok, _game, 1} =
             Games.create(game_id)

    {:ok, view, _html} =
      live(conn, "/games")

    view
    |> form("#open-game-#{game_id}", %{
      "game_id" => game_id,
      "room" => %{"id" => room_id}
    })
    |> render_submit()

    assert_redirect(
      view,
      "/rooms/#{room_id}?game_id=#{game_id}"
    )

    assert {:ok, room} = Rooms.get(room_id)
    assert game_id in room.game_ids
  end
end
