defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

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

  test "updates all connected LiveViews when a game is added", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, view1, _html} = live(conn, "/rooms/#{room_id}")
    {:ok, view2, _html} = live(conn, "/rooms/#{room_id}")

    refute render(view1) =~ "game-1"
    refute render(view2) =~ "game-1"

    view1
    |> form("#add-game-form", %{"game" => %{"id" => "game-1"}})
    |> render_submit()

    assert render(view1) =~ "game-1"
    assert render(view2) =~ "game-1"
  end

  test "adds a game to the room", %{conn: conn, room_id: room_id} do
    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> form("#add-game-form", %{"game" => %{"id" => "game-1"}})
    |> render_submit()

    assert {:ok, room} = Rooms.get(room_id)
    assert room.game_ids == ["game-1"]

    assert render(view) =~ "game-1"
  end
end
