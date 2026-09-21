defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.PositionStore
  alias Analysis.Rooms
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp insert_game_with_moves do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    game_id
  end

  defp insert_game do
    game_id = "game-#{System.unique_integer([:positive])}"
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    game_id
  end

  defp insert_playable_game do
    game_id = "game-#{System.unique_integer([:positive])}"
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    game_id
  end

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

  test "selects a game from the room", %{conn: conn, room_id: room_id} do
    game_id = insert_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    refute has_element?(view, "#selected-game")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#selected-game")
    assert has_element?(view, "#selected-game-id", game_id)
    assert has_element?(view, "#selected-game-revision", "Revision 1")
  end

  test "refreshes the selected game when it changes", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert has_element?(view, "#selected-game-revision", "Revision 2")
  end

  test "switches the game event subscription when another game is selected", %{
    conn: conn,
    room_id: room_id
  } do
    first_game_id = insert_playable_game()
    second_game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, first_game_id)
    assert :ok = Rooms.add_game(room_id, second_game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{first_game_id}")
    |> render_click()

    view
    |> element("#select-game-#{second_game_id}")
    |> render_click()

    assert has_element?(view, "#selected-game-id", second_game_id)
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, _game, 2, [0]} =
             Games.play(first_game_id, [], move("e2", "e4"))

    assert has_element?(view, "#selected-game-id", second_game_id)
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, _game, 2, [0]} =
             Games.play(second_game_id, [], move("e2", "e4"))

    assert has_element?(view, "#selected-game-revision", "Revision 2")
  end

  test "navigates through the selected game tree", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_game_with_moves()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#navigate-child-0")
    refute has_element?(view, "#navigate-parent")

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#navigate-parent")
    assert has_element?(view, "#navigate-child-0")

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0]")
    refute has_element?(view, "#navigate-child-0")

    view
    |> element("#navigate-parent")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0]")
  end

  test "connected LiveViews navigate independently", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_game_with_moves()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view1, _html} = live(conn, "/rooms/#{room_id}")
    {:ok, view2, _html} = live(conn, "/rooms/#{room_id}")

    view1
    |> element("#select-game-#{game_id}")
    |> render_click()

    view2
    |> element("#select-game-#{game_id}")
    |> render_click()

    view1
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view1, "#current-path", "Path [0]")
    assert has_element?(view2, "#current-path", "Path []")
  end
end
