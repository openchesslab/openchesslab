defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.Rooms

  setup do
    room_id = "room-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Rooms.stop_room(room_id)
    end)

    %{room_id: room_id}
  end

  test "starts and renders a room", %{conn: conn, room_id: room_id} do
    assert :not_found = Rooms.get(room_id)

    {:ok, _view, html} = live(conn, "/rooms/#{room_id}")

    assert html =~ room_id
    assert {:ok, room} = Rooms.get(room_id)
    assert room.id == room_id
    assert room.game_ids == []
  end

  test "renders games already present in the room", %{
    conn: conn,
    room_id: room_id
  } do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")
    assert :ok = Rooms.add_game(room_id, "game-2")

    {:ok, _view, html} = live(conn, "/rooms/#{room_id}")

    assert html =~ "game-1"
    assert html =~ "game-2"
  end

  test "adds a game to the room", %{conn: conn, room_id: room_id} do
    game_id = insert_game()

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> form("#add-game-form", %{"game" => %{"id" => game_id}})
    |> render_submit()

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == [game_id]
    assert render(view) =~ game_id
  end

  test "removes a game from the room", %{conn: conn, room_id: room_id} do
    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, "game-1")

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    assert render(view) =~ "game-1"

    view
    |> element("#remove-game-game-1")
    |> render_click()

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == []

    refute render(view) =~ "game-1"
  end

  test "updates all connected LiveViews when a game is added", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_game()

    {:ok, view1, _html} = live(conn, "/rooms/#{room_id}")
    {:ok, view2, _html} = live(conn, "/rooms/#{room_id}")

    refute render(view1) =~ game_id
    refute render(view2) =~ game_id

    view1
    |> form("#add-game-form", %{"game" => %{"id" => game_id}})
    |> render_submit()

    assert render(view1) =~ game_id
    assert render(view2) =~ game_id
  end

  test "does not add an unknown game", %{conn: conn, room_id: room_id} do
    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> form("#add-game-form", %{"game" => %{"id" => "unknown-game"}})
    |> render_submit()

    assert render(view) =~ "Game not found."

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == []
  end

  test "clears the error after adding an existing game", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_game()

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> form("#add-game-form", %{"game" => %{"id" => "unknown-#{game_id}"}})
    |> render_submit()

    assert render(view) =~ "Game not found."

    view
    |> form("#add-game-form", %{"game" => %{"id" => game_id}})
    |> render_submit()

    refute render(view) =~ "Game not found."
    assert render(view) =~ game_id
  end

  defp insert_game do
    game_id = "game-#{System.unique_integer([:positive])}"
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    game_id
  end
end
