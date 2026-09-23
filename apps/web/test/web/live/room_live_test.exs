defmodule Web.RoomLiveTest do
  use Web.ConnCase, async: false

  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Rooms
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  defp with_locale(conn, locale) do
    conn
    |> init_test_session(%{})
    |> put_session(
      Localize.Plug.PutLocale.session_key(),
      locale
    )
  end

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
    game_id = insert_playable_game()

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
    game_id = insert_playable_game()

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
    game_id = insert_playable_game()

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
    game_id = insert_playable_game()

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

    assert has_element?(
             view,
             "#navigate-child-0",
             "e4"
           )

    refute has_element?(view, "#navigate-parent")

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#navigate-parent")
    assert has_element?(view, "#navigate-child-0")

    assert has_element?(
             view,
             "#navigate-child-0",
             "e5"
           )

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

  test "plays a move from the current path and navigates to the result", %{
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

    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    view
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "e2",
        "to" => "e4"
      }
    })
    |> render_submit()

    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#selected-game-revision", "Revision 2")

    assert {:ok, game, 2} = Games.get(game_id)
    assert Game.node_at(game, [0])
  end

  test "renders the position for the current occurrence", %{
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

    assert has_element?(view, "#piece-e2")
    refute has_element?(view, "#piece-e4")

    view
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "e2",
        "to" => "e4"
      }
    })
    |> render_submit()

    refute has_element?(view, "#piece-e2")
    assert has_element?(view, "#piece-e4")

    view
    |> element("#navigate-parent")
    |> render_click()

    assert has_element?(view, "#piece-e2")
    refute has_element?(view, "#piece-e4")
  end

  test "plays a move from the current occurrence", %{
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

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0]")

    view
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "g1",
        "to" => "f3"
      }
    })
    |> render_submit()

    assert has_element?(view, "#current-path", "Path [0, 0, 0]")

    assert {:ok, game, 4} = Games.get(game_id)
    assert Game.node_at(game, [0, 0, 0])
  end

  test "shows an error and stays at the current path for an illegal move", %{
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

    view
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "e2",
        "to" => "e5"
      }
    })
    |> render_submit()

    assert has_element?(view, "#move-error", "Illegal move.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")
  end

  test "shows an error for an invalid square", %{
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

    view
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "foo",
        "to" => "e4"
      }
    })
    |> render_submit()

    assert has_element?(view, "#move-error", "Invalid square.")
    assert has_element?(view, "#current-path", "Path []")
  end

  test "a played move updates both views but only moves the initiating path", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

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
    |> form("#play-move-form", %{
      "move" => %{
        "from" => "e2",
        "to" => "e4"
      }
    })
    |> render_submit()

    assert has_element?(view1, "#selected-game-revision", "Revision 2")
    assert has_element?(view2, "#selected-game-revision", "Revision 2")

    assert has_element?(view1, "#current-path", "Path [0]")
    assert has_element?(view2, "#current-path", "Path []")

    assert has_element?(view2, "#navigate-child-0")
  end

  test "falls back to the surviving ancestor when another user removes the current subtree", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 0, 0]} =
             Games.play(game_id, [0, 0], move("g1", "f3"))

    assert {:ok, _game, 5, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0, 0]")

    assert {:ok, _game, 6, [0]} =
             Games.remove(game_id, [0, 0])

    assert has_element?(view, "#selected-game-revision", "Revision 6")
    assert has_element?(view, "#current-path", "Path [0]")
  end

  test "follows the current occurrence when another user promotes its variation", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _game, 5, [0, 1, 0]} =
             Games.play(game_id, [0, 1], move("g1", "f3"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-1")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 1, 0]")

    assert {:ok, _game, 6, [0, 0]} =
             Games.promote(game_id, [0, 1])

    assert has_element?(view, "#selected-game-revision", "Revision 6")

    assert has_element?(view, "#current-path", "Path [0, 0, 0]")
  end

  test "plays a move by clicking two board squares", %{
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

    assert has_element?(view, "#piece-e2")
    refute has_element?(view, "#piece-e4")

    view
    |> element("#square-e2")
    |> render_click()

    view
    |> element("#square-e4")
    |> render_click()

    refute has_element?(view, "#piece-e2")
    assert has_element?(view, "#piece-e4")
    assert has_element?(view, "#current-path", "Path [0]")
  end

  test "removes a piece from the current position and navigates to the result", %{
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

    assert has_element?(view, "#piece-e2")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    view
    |> form("#remove-piece-form", %{
      "edit" => %{"square" => "e2"}
    })
    |> render_submit()

    refute has_element?(view, "#piece-e2")
    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#selected-game-revision", "Revision 2")

    assert {:ok, game, 2} = Games.get(game_id)

    child = Game.node_at(game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             edited_position,
             Square.from_algebraic("e2")
           ) == nil
  end

  test "shows an error and stays at the current path for an invalid edit", %{
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

    view
    |> form("#remove-piece-form", %{
      "edit" => %{"square" => "e1"}
    })
    |> render_submit()

    assert has_element?(view, "#edit-error", "Invalid position.")
    assert has_element?(view, "#piece-e1")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, game, 1} = Games.get(game_id)
    assert Game.node_at(game, [0]) == nil
  end

  test "shows an error for an invalid edit square", %{
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

    view
    |> form("#remove-piece-form", %{
      "edit" => %{"square" => "foo"}
    })
    |> render_submit()

    assert has_element?(view, "#edit-error", "Invalid square.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")
  end

  test "puts a piece on the current position and navigates to the result", %{
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

    view
    |> form("#remove-piece-form", %{
      "edit" => %{"square" => "e2"}
    })
    |> render_submit()

    assert has_element?(view, "#current-path", "Path [0]")
    refute has_element?(view, "#piece-e2")
    refute has_element?(view, "#piece-e3")

    view
    |> form("#put-piece-form", %{
      "edit" => %{
        "square" => "e3",
        "color" => "white",
        "piece" => "pawn"
      }
    })
    |> render_submit()

    assert has_element?(view, "#piece-e3")
    assert has_element?(view, "#current-path", "Path [0, 0]")
    assert has_element?(view, "#selected-game-revision", "Revision 3")

    assert {:ok, game, 3} = Games.get(game_id)

    child = Game.node_at(game, [0, 0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             edited_position,
             Square.from_algebraic("e3")
           ) == {:white, :pawn}
  end

  test "shows an error for an invalid put piece square", %{
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

    view
    |> form("#put-piece-form", %{
      "edit" => %{
        "square" => "foo",
        "color" => "white",
        "piece" => "queen"
      }
    })
    |> render_submit()

    assert has_element?(view, "#edit-error", "Invalid square.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")
  end

  test "shows an error for an invalid piece", %{
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

    render_submit(view, "put_piece", %{
      "edit" => %{
        "square" => "e4",
        "color" => "white",
        "piece" => "dragon"
      }
    })

    assert has_element?(view, "#edit-error", "Invalid piece.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, game, 1} = Games.get(game_id)
    assert Game.node_at(game, [0]) == nil
  end

  test "changes the side to move and navigates to the result", %{
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

    assert has_element?(view, "#side-to-move", "White")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    view
    |> form("#side-to-move-form", %{
      "edit" => %{"side_to_move" => "black"}
    })
    |> render_submit()

    assert has_element?(view, "#side-to-move", "Black")
    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#selected-game-revision", "Revision 2")

    assert {:ok, game, 2} = Games.get(game_id)

    child = Game.node_at(game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert edited_position.side_to_move == :black
  end

  test "shows an error for an invalid side to move", %{
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

    render_submit(view, "set_side_to_move", %{
      "edit" => %{"side_to_move" => "green"}
    })

    assert has_element?(view, "#edit-error", "Invalid side to move.")
    assert has_element?(view, "#side-to-move", "White")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, game, 1} = Games.get(game_id)
    assert Game.node_at(game, [0]) == nil
  end

  test "disables a castling right and navigates to the result", %{
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

    assert has_element?(view, "#castling-white-kingside", "Enabled")

    view
    |> form("#castling-right-form", %{
      "edit" => %{
        "right" => "white_kingside",
        "enabled" => "false"
      }
    })
    |> render_submit()

    assert has_element?(view, "#castling-white-kingside", "Disabled")
    assert has_element?(view, "#current-path", "Path [0]")
    assert has_element?(view, "#selected-game-revision", "Revision 2")

    assert {:ok, game, 2} = Games.get(game_id)

    child = Game.node_at(game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    refute MapSet.member?(
             edited_position.castling_rights,
             :white_kingside
           )
  end

  test "enables a castling right and navigates to the result", %{
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

    view
    |> form("#castling-right-form", %{
      "edit" => %{
        "right" => "white_kingside",
        "enabled" => "false"
      }
    })
    |> render_submit()

    assert has_element?(view, "#castling-white-kingside", "Disabled")

    view
    |> form("#castling-right-form", %{
      "edit" => %{
        "right" => "white_kingside",
        "enabled" => "true"
      }
    })
    |> render_submit()

    assert has_element?(view, "#castling-white-kingside", "Enabled")
    assert has_element?(view, "#current-path", "Path [0, 0]")
    assert has_element?(view, "#selected-game-revision", "Revision 3")

    assert {:ok, game, 3} = Games.get(game_id)

    child = Game.node_at(game, [0, 0])

    assert %Node{} = child

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert MapSet.member?(
             edited_position.castling_rights,
             :white_kingside
           )
  end

  test "shows an error for an invalid castling right", %{
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

    render_submit(view, "set_castling_right", %{
      "edit" => %{
        "right" => "white_center",
        "enabled" => "true"
      }
    })

    assert has_element?(view, "#edit-error", "Invalid castling right.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, game, 1} = Games.get(game_id)
    assert Game.node_at(game, [0]) == nil
  end

  test "sets an en passant target and navigates to the result", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("a7", "a6"))

    assert {:ok, _game, 4, [0, 0, 0]} =
             Games.play(game_id, [0, 0], move("e4", "e5"))

    assert {:ok, _game, 5, [0, 0, 0, 0]} =
             Games.play(game_id, [0, 0, 0], move("d7", "d5"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view |> element("#navigate-child-0") |> render_click()
    view |> element("#navigate-child-0") |> render_click()
    view |> element("#navigate-child-0") |> render_click()
    view |> element("#navigate-child-0") |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0, 0, 0]")
    assert has_element?(view, "#en-passant", "d6")

    view
    |> form("#en-passant-form", %{
      "edit" => %{"en_passant" => "none"}
    })
    |> render_submit()

    assert has_element?(view, "#en-passant", "None")
    assert has_element?(view, "#current-path", "Path [0, 0, 0, 0, 0]")
    assert has_element?(view, "#selected-game-revision", "Revision 6")

    assert {:ok, game, 6} = Games.get(game_id)

    child = Game.node_at(game, [0, 0, 0, 0, 0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert edited_position.en_passant == nil
  end

  test "shows an error for an invalid en passant square", %{
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

    view
    |> form("#en-passant-form", %{
      "edit" => %{"en_passant" => "foo"}
    })
    |> render_submit()

    assert has_element?(view, "#edit-error", "Invalid en passant square.")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")
  end

  test "rejects an inconsistent en passant target", %{
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

    view
    |> form("#en-passant-form", %{
      "edit" => %{"en_passant" => "d6"}
    })
    |> render_submit()

    assert has_element?(view, "#edit-error", "Invalid position.")
    assert has_element?(view, "#en-passant", "None")
    assert has_element?(view, "#current-path", "Path []")
    assert has_element?(view, "#selected-game-revision", "Revision 1")

    assert {:ok, game, 1} = Games.get(game_id)
    assert Game.node_at(game, [0]) == nil
  end

  test "promotes the current variation and follows it to its new path", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-1")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 1]")
    assert has_element?(view, "#promote-variation")

    view
    |> element("#promote-variation")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0]")
    assert has_element?(view, "#selected-game-revision", "Revision 5")

    assert {:ok, game, 5} = Games.get(game_id)

    promoted = Game.node_at(game, [0, 0])
    previous_main = Game.node_at(game, [0, 1])

    assert Node.transition(promoted) ==
             Transition.move(move("c7", "c5"))

    assert Node.transition(previous_main) ==
             Transition.move(move("e7", "e5"))

    refute has_element?(view, "#promote-variation")
  end

  test "removes the current subtree and navigates to its parent", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _game, 5, [0, 1, 0]} =
             Games.play(game_id, [0, 1], move("g1", "f3"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    view
    |> element("#navigate-child-1")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 1, 0]")
    assert has_element?(view, "#remove-subtree")

    view
    |> element("#remove-subtree")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 1]")
    assert has_element?(view, "#selected-game-revision", "Revision 6")

    assert {:ok, game, 6} = Games.get(game_id)

    assert Game.node_at(game, [0, 1, 0]) == nil

    remaining = Game.node_at(game, [0, 1])

    assert Node.transition(remaining) ==
             Transition.move(move("c7", "c5"))

    refute has_element?(view, "#navigate-child-0")
  end

  test "does not offer subtree removal for the root", %{
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

    assert has_element?(view, "#current-path", "Path []")
    refute has_element?(view, "#remove-subtree")
  end

  test "sets a comment on the current occurrence", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#current-comment", "No comment")

    view
    |> form("#comment-form", %{
      "comment" => %{
        "text" => "Interesting position"
      }
    })
    |> render_submit()

    assert has_element?(
             view,
             "#current-comment",
             "Interesting position"
           )

    assert has_element?(
             view,
             "#selected-game-revision",
             "Revision 3"
           )

    assert has_element?(view, "#current-path", "Path [0]")

    assert {:ok, game, 3} = Games.get(game_id)

    assert game
           |> Game.node_at([0])
           |> Node.comment() == "Interesting position"
  end

  test "clears the comment on the current occurrence", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2} =
             Games.set_comment(
               game_id,
               [],
               "Temporary comment"
             )

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} = live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(
             view,
             "#current-comment",
             "Temporary comment"
           )

    view
    |> form("#comment-form", %{
      "comment" => %{
        "text" => ""
      }
    })
    |> render_submit()

    assert has_element?(view, "#current-comment", "No comment")

    assert has_element?(
             view,
             "#selected-game-revision",
             "Revision 3"
           )

    assert {:ok, game, 3} = Games.get(game_id)
    assert Node.comment(Game.root(game)) == nil
  end

  test "shows move notation for alternative continuations", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(
             view,
             "#navigate-child-0",
             "e5"
           )

    assert has_element?(
             view,
             "#navigate-child-1",
             "c5"
           )
  end

  test "renders the main line with move numbers and notation", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 0, 0]} =
             Games.play(game_id, [0, 0], move("g1", "f3"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#move-tree-0", "1. e4")
    assert has_element?(view, "#move-tree-0-0", "1... e5")
    assert has_element?(view, "#move-tree-0-0-0", "2. Nf3")
  end

  test "navigates directly from the move tree", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_game_with_moves()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#move-tree-0-0")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 0]")
  end

  test "renders variations in the move tree", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 0, 0]} =
             Games.play(game_id, [0, 0], move("g1", "f3"))

    assert {:ok, _game, 5, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _game, 6, [0, 1, 0]} =
             Games.play(game_id, [0, 1], move("g1", "f3"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#move-tree-0", "1. e4")
    assert has_element?(view, "#move-tree-0-0", "1... e5")
    assert has_element?(view, "#move-tree-0-0-0", "2. Nf3")

    assert has_element?(view, "#move-tree-0-1", "1... c5")
    assert has_element?(view, "#move-tree-0-1-0", "2. Nf3")

    view
    |> element("#move-tree-0-1")
    |> render_click()

    assert has_element?(view, "#current-path", "Path [0, 1]")
  end

  test "shows localized move notation for alternative continuations", %{
    conn: conn,
    room_id: room_id
  } do
    conn = with_locale(conn, "nl")

    game_id = insert_playable_game()

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, _game, 3, [0, 0]} =
             Games.play(game_id, [0], move("e7", "e5"))

    assert {:ok, _game, 4, [0, 1]} =
             Games.play(game_id, [0], move("c7", "c5"))

    assert {:ok, _game, 5, [0, 0, 0]} =
             Games.play(game_id, [0, 0], move("g1", "f3"))

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#navigate-child-0", "e5")
    assert has_element?(view, "#navigate-child-1", "c5")

    view
    |> element("#navigate-child-0")
    |> render_click()

    assert has_element?(view, "#navigate-child-0", "Pf3")
  end

  test "uses the locale from the session", %{conn: conn, room_id: room_id} do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    conn = with_locale(conn, "nl")

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert render(view) =~ "Geselecteerde partij"
  end

  test "localizes edited positions in the move tree", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    conn = with_locale(conn, "nl")

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    view
    |> form("#side-to-move-form", %{
      "edit" => %{"side_to_move" => "black"}
    })
    |> render_submit()

    assert has_element?(
             view,
             "#move-tree-0",
             "Bewerkte stelling"
           )
  end

  test "localizes the room interface", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    conn = with_locale(conn, "nl")

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    assert has_element?(view, "h1", "Ruimte #{room_id}")
    assert has_element?(view, "#add-game-form button", "Partij toevoegen")
    assert has_element?(view, "#select-game-#{game_id}", "Selecteren")
    assert has_element?(view, "#remove-game-#{game_id}", "Verwijderen")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#selected-game h2", "Geselecteerde partij")
    assert has_element?(view, "#selected-game-revision", "Revisie 1")
    assert has_element?(view, "#current-path", "Pad []")
    assert has_element?(view, "#play-move-form button", "Zet spelen")
    assert has_element?(view, "#current-comment", "Geen commentaar")
    assert has_element?(view, "#comment-form button", "Commentaar opslaan")
  end

  test "uses English as the default locale", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(view, "#selected-game h2", "Selected game")
    assert has_element?(view, "#side-to-move", "White")
    assert has_element?(view, "#current-path", "Path []")
  end

  test "uses the browser locale on the first request", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    conn =
      put_req_header(
        conn,
        "accept-language",
        "nl-NL,nl;q=0.9,en;q=0.8"
      )

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(
             view,
             "#selected-game h2",
             "Geselecteerde partij"
           )

    assert has_element?(
             view,
             "#side-to-move",
             "Wit"
           )
  end

  test "an explicit locale overrides the browser locale", %{
    conn: conn,
    room_id: room_id
  } do
    game_id = insert_playable_game()

    assert {:ok, _room} = Rooms.start_room(room_id)
    assert :ok = Rooms.add_game(room_id, game_id)

    conn =
      put_req_header(
        conn,
        "accept-language",
        "nl-NL,nl;q=0.9"
      )

    {:ok, view, _html} =
      live(conn, "/rooms/#{room_id}?locale=en")

    view
    |> element("#select-game-#{game_id}")
    |> render_click()

    assert has_element?(
             view,
             "#selected-game h2",
             "Selected game"
           )

    assert has_element?(
             view,
             "#side-to-move",
             "White"
           )
  end
end
