defmodule Analysis.GamesTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft
  alias Chess.Square

  defp game_with_variations(game_id) do
    Game.new(game_id, 1)
    |> Game.add_child([], transition("e2", "e4"), 2)
    |> Game.add_child([], transition("d2", "d4"), 3)
    |> Game.add_child([], transition("c2", "c4"), 4)
  end

  defp transition(from, to) do
    Transition.move(move(from, to))
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  setup do
    game_id = "game-#{System.unique_integer([:positive])}"

    %{game_id: game_id}
  end

  describe "create/1" do
    test "creates a game from the standard starting position", %{
      game_id: game_id
    } do
      assert {:ok, game, 1} = Games.create(game_id)

      assert game.id == game_id
      assert Game.start(game) == Analysis.GameStart.standard()

      root = Game.root(game)

      assert {:ok, position} =
               PositionStore.get(Node.position_id(root))

      assert position == Position.starting_position()

      assert {:ok, ^game, 1} = Games.get(game_id)
    end

    test "does not create the same game twice", %{
      game_id: game_id
    } do
      assert {:ok, _game, 1} = Games.create(game_id)

      assert {:error, :already_exists} =
               Games.create(game_id)
    end
  end

  test "gets a stored game", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns not_found for an unknown game", %{game_id: game_id} do
    assert :not_found = Games.get(game_id)
  end

  test "does not insert the same game twice", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)
    assert {:error, :already_exists} = Games.insert(game)
  end

  test "plays a move and persists the updated game", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    e4 = move("e2", "e4")

    assert {:ok, updated_game, 2, [0]} =
             Games.play(game_id, [], e4)

    child = Game.node_at(updated_game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.move(e4)

    assert {:ok, ^updated_game, 2} = Games.get(game_id)

    assert {:ok, position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             position,
             Square.from_algebraic("e4")
           ) == {:white, :pawn}

    assert position.side_to_move == :black
  end

  test "returns game_not_found for an unknown game", %{game_id: game_id} do
    assert Games.play(game_id, [], move("e2", "e4")) ==
             {:error, :game_not_found}
  end

  test "returns node_not_found for an unknown path", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [0], move("e2", "e4")) ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns position_not_found when the node position does not exist", %{
    game_id: game_id
  } do
    game = Game.new(game_id, 999_999_999)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [], move("e2", "e4")) ==
             {:error, :position_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns illegal_move without updating the game", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [], move("e2", "e5")) ==
             {:error, :illegal_move}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "playing an existing continuation does not duplicate it", %{
    game_id: game_id
  } do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, game, 3, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert length(Node.children(Game.root(game))) == 1
  end

  test "sets a comment and persists the updated game", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2} =
             Games.set_comment(game_id, [], "Interesting position")

    assert Node.comment(Game.root(updated_game)) ==
             "Interesting position"

    assert {:ok, ^updated_game, 2} = Games.get(game_id)
  end

  test "sets a comment on a child node", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, updated_game, 3} =
             Games.set_comment(game_id, [0], "King's Pawn")

    assert updated_game
           |> Game.node_at([0])
           |> Node.comment() == "King's Pawn"

    assert {:ok, ^updated_game, 3} = Games.get(game_id)
  end

  test "removes a comment with nil", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, _game, 2} =
             Games.set_comment(game_id, [], "Temporary")

    assert {:ok, updated_game, 3} =
             Games.set_comment(game_id, [], nil)

    assert Node.comment(Game.root(updated_game)) == nil
    assert {:ok, ^updated_game, 3} = Games.get(game_id)
  end

  test "returns game_not_found when setting a comment on an unknown game", %{
    game_id: game_id
  } do
    assert Games.set_comment(game_id, [], "Comment") ==
             {:error, :game_not_found}
  end

  test "returns node_not_found when setting a comment on an unknown path", %{
    game_id: game_id
  } do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert Games.set_comment(game_id, [0], "Comment") ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "publishes a game change after setting a comment", %{
    game_id: game_id
  } do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    :ok = Analysis.GameEvents.subscribe(game_id)

    assert {:ok, _game, 2} =
             Games.set_comment(game_id, [], "Comment")

    assert_receive {:game_changed, ^game_id}
  end

  test "does not publish a game change when setting a comment fails", %{
    game_id: game_id
  } do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    :ok = Analysis.GameEvents.subscribe(game_id)

    assert Games.set_comment(game_id, [0], "Comment") ==
             {:error, :node_not_found}

    refute_receive {:game_changed, ^game_id}
  end

  test "promotes a variation and persists the updated game", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2, [0]} =
             Games.promote(game_id, [1])

    assert updated_game
           |> Game.node_at([0])
           |> Node.transition() == transition("d2", "d4")

    assert updated_game
           |> Game.node_at([1])
           |> Node.transition() == transition("e2", "e4")

    assert updated_game
           |> Game.node_at([2])
           |> Node.transition() == transition("c2", "c4")

    assert {:ok, ^updated_game, 2} = Games.get(game_id)
  end

  test "promotes a nested variation and returns its new path", %{
    game_id: game_id
  } do
    game =
      Game.new(game_id, 1)
      |> Game.add_child([], transition("e2", "e4"), 2)
      |> Game.add_child([0], transition("e7", "e5"), 3)
      |> Game.add_child([0], transition("c7", "c5"), 4)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2, [0, 0]} =
             Games.promote(game_id, [0, 1])

    assert updated_game
           |> Game.node_at([0, 0])
           |> Node.transition() == transition("c7", "c5")

    assert updated_game
           |> Game.node_at([0, 1])
           |> Node.transition() == transition("e7", "e5")
  end

  test "returns game_not_found when promoting in an unknown game", %{
    game_id: game_id
  } do
    assert Games.promote(game_id, [0]) ==
             {:error, :game_not_found}
  end

  test "returns root when promoting the root", %{game_id: game_id} do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.promote(game_id, []) ==
             {:error, :root}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns node_not_found when promoting an unknown path", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.promote(game_id, [99]) ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "publishes a game change after promoting a variation", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    :ok = Analysis.GameEvents.subscribe(game_id)

    assert {:ok, _game, 2, [0]} =
             Games.promote(game_id, [1])

    assert_receive {:game_changed, ^game_id}
  end

  test "removes a variation and persists the updated game", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2, []} =
             Games.remove(game_id, [1])

    assert updated_game
           |> Game.node_at([0])
           |> Node.transition() == transition("e2", "e4")

    assert updated_game
           |> Game.node_at([1])
           |> Node.transition() == transition("c2", "c4")

    assert Game.node_at(updated_game, [2]) == nil

    assert {:ok, ^updated_game, 2} = Games.get(game_id)
  end

  test "removes a nested variation subtree and returns its parent path", %{
    game_id: game_id
  } do
    game =
      Game.new(game_id, 1)
      |> Game.add_child([], transition("e2", "e4"), 2)
      |> Game.add_child([0], transition("e7", "e5"), 3)
      |> Game.add_child([0, 0], transition("g1", "f3"), 4)
      |> Game.add_child([0], transition("c7", "c5"), 5)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2, [0]} =
             Games.remove(game_id, [0, 0])

    assert updated_game
           |> Game.node_at([0, 0])
           |> Node.transition() == transition("c7", "c5")

    assert Game.node_at(updated_game, [0, 0, 0]) == nil

    assert {:ok, ^updated_game, 2} = Games.get(game_id)
  end

  test "returns game_not_found when removing from an unknown game", %{
    game_id: game_id
  } do
    assert Games.remove(game_id, [0]) ==
             {:error, :game_not_found}
  end

  test "returns root when removing the root", %{game_id: game_id} do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.remove(game_id, []) ==
             {:error, :root}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns node_not_found when removing an unknown path", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.remove(game_id, [99]) ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "publishes a game change after removing a variation", %{
    game_id: game_id
  } do
    game = game_with_variations(game_id)

    assert {:ok, 1} = Games.insert(game)

    :ok = Analysis.GameEvents.subscribe(game_id)

    assert {:ok, _game, 2, []} =
             Games.remove(game_id, [1])

    assert_receive {:game_changed, ^game_id}
  end

  test "edits a position and persists the updated game", %{
    game_id: game_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.remove_piece(Square.from_algebraic("e2"))

    assert {:ok, updated_game, 2, [0]} =
             Games.edit(game_id, [], draft)

    child = Game.node_at(updated_game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, ^updated_game, 2} = Games.get(game_id)

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             edited_position,
             Square.from_algebraic("e2")
           ) == nil
  end

  test "returns game_not_found when editing an unknown game", %{
    game_id: game_id
  } do
    position = Position.new()

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.put_piece(
        Square.from_algebraic("e1"),
        {:white, :king}
      )
      |> PositionDraft.put_piece(
        Square.from_algebraic("e8"),
        {:black, :king}
      )

    assert Games.edit(game_id, [], draft) ==
             {:error, :game_not_found}
  end

  test "returns node_not_found when editing an unknown path", %{
    game_id: game_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.put_piece(
        Square.from_algebraic("e1"),
        {:white, :king}
      )
      |> PositionDraft.put_piece(
        Square.from_algebraic("e8"),
        {:black, :king}
      )

    assert Games.edit(game_id, [0], draft) ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns invalid_position without updating the game", %{
    game_id: game_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.remove_piece(Square.from_algebraic("e1"))

    assert {:error, {:invalid_position, reasons}} =
             Games.edit(game_id, [], draft)

    assert reasons != []
    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "editing the same position does not duplicate the continuation", %{
    game_id: game_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.put_piece(
        Square.from_algebraic("e1"),
        {:white, :king}
      )
      |> PositionDraft.put_piece(
        Square.from_algebraic("e8"),
        {:black, :king}
      )

    assert {:ok, _game, 2, [0]} =
             Games.edit(game_id, [], draft)

    assert {:ok, updated_game, 3, [0]} =
             Games.edit(game_id, [], draft)

    assert length(Node.children(Game.root(updated_game))) == 1
  end

  test "publishes a game change after editing a position", %{
    game_id: game_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    :ok = Analysis.GameEvents.subscribe(game_id)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.put_piece(
        Square.from_algebraic("e1"),
        {:white, :king}
      )
      |> PositionDraft.put_piece(
        Square.from_algebraic("e8"),
        {:black, :king}
      )

    assert {:ok, _game, 2, [0]} =
             Games.edit(game_id, [], draft)

    assert_receive {:game_changed, ^game_id}
  end
end
