defmodule AnalysisTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameStore.Memory
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias Chess.Square

  defp new_db do
    PositionDB.new(
      key_function: &PositionKey.exact/1,
      properties: [
        {:open_files, &PositionProperties.open_files/1},
        {:material, &PositionProperties.material/1}
      ]
    )
  end

  defp new_game do
    position = Position.starting_position()
    db = new_db()

    {db, position_id} = PositionDB.append(db, position)

    {Game.new("game-1", position_id), db}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  test "plays a move and adds the resulting position to the game tree" do
    {game, db} = new_game()

    e4 = move("e2", "e4")

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], e4)

    child = Game.node_at(game, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.move(e4)

    assert {:ok, position} =
             PositionDB.get(db, Node.position_id(child))

    assert Position.piece_at(position, Square.from_algebraic("e4")) ==
             {:white, :pawn}

    assert Position.piece_at(position, Square.from_algebraic("e2")) ==
             nil

    assert position.side_to_move == :black
  end

  test "plays consecutive moves from their specific occurrences" do
    {game, db} = new_game()

    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], e4)

    assert {:ok, game, db, [0, 0]} =
             Analysis.play(game, db, [0], e5)

    e4_node = Game.node_at(game, [0])
    e5_node = Game.node_at(game, [0, 0])

    assert Node.transition(e4_node) == Transition.move(e4)
    assert Node.transition(e5_node) == Transition.move(e5)

    assert {:ok, position} =
             PositionDB.get(db, Node.position_id(e5_node))

    assert Position.piece_at(position, Square.from_algebraic("e4")) ==
             {:white, :pawn}

    assert Position.piece_at(position, Square.from_algebraic("e5")) ==
             {:black, :pawn}

    assert position.side_to_move == :white
  end

  test "playing from an earlier occurrence creates a variation" do
    {game, db} = new_game()

    e4 = move("e2", "e4")
    d4 = move("d2", "d4")

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], e4)

    assert {:ok, game, _db, [1]} =
             Analysis.play(game, db, [], d4)

    children = game |> Game.root() |> Node.children()

    assert Enum.map(children, &Node.transition/1) ==
             [Transition.move(e4), Transition.move(d4)]

    assert Game.node_at(game, [0]) != nil
    assert Game.node_at(game, [1]) != nil
  end

  test "returns an error for an illegal move" do
    {game, db} = new_game()

    illegal_move = move("e2", "e5")

    assert Analysis.play(game, db, [], illegal_move) ==
             {:error, :illegal_move}

    assert Node.children(Game.root(game)) == []
  end

  test "returns an error for a nonexistent path" do
    {game, db} = new_game()

    assert Analysis.play(game, db, [0], move("e2", "e4")) ==
             {:error, :node_not_found}
  end

  test "returns an error when the node position does not exist in PositionDB" do
    db = new_db()
    game = Game.new("game-1", 999)

    assert Analysis.play(game, db, [], move("e2", "e4")) ==
             {:error, :position_not_found}
  end

  test "reuses an existing PositionDB position reached through a transposition" do
    {game, db} = new_game()

    # First move order:
    # 1. Nf3 Nf6 2. g3 g6

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], move("g1", "f3"))

    assert {:ok, game, db, [0, 0]} =
             Analysis.play(game, db, [0], move("g8", "f6"))

    assert {:ok, game, db, [0, 0, 0]} =
             Analysis.play(game, db, [0, 0], move("g2", "g3"))

    assert {:ok, game, db, [0, 0, 0, 0]} =
             Analysis.play(game, db, [0, 0, 0], move("g7", "g6"))

    first_node = Game.node_at(game, [0, 0, 0, 0])
    first_position_id = Node.position_id(first_node)

    # Second move order:
    # 1. g3 g6 2. Nf3 Nf6

    assert {:ok, game, db, [1]} =
             Analysis.play(game, db, [], move("g2", "g3"))

    assert {:ok, game, db, [1, 0]} =
             Analysis.play(game, db, [1], move("g7", "g6"))

    assert {:ok, game, db, [1, 0, 0]} =
             Analysis.play(game, db, [1, 0], move("g1", "f3"))

    assert {:ok, game, _db, [1, 0, 0, 0]} =
             Analysis.play(game, db, [1, 0, 0], move("g8", "f6"))

    second_node = Game.node_at(game, [1, 0, 0, 0])
    second_position_id = Node.position_id(second_node)

    assert first_node != second_node
    assert first_position_id == second_position_id
  end

  test "returns the path of the newly created occurrence" do
    {game, db} = new_game()

    assert {:ok, game, _db, [0]} =
             Analysis.play(game, db, [], move("e2", "e4"))

    assert Game.node_at(game, [0]) != nil
  end

  test "returns the path of a nested occurrence" do
    {game, db} = new_game()

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], move("e2", "e4"))

    assert {:ok, game, _db, [0, 0]} =
             Analysis.play(game, db, [0], move("e7", "e5"))

    assert Game.node_at(game, [0, 0]) != nil
  end

  test "playing an existing move returns its existing path" do
    {game, db} = new_game()
    e4 = move("e2", "e4")

    assert {:ok, game, db, [0]} =
             Analysis.play(game, db, [], e4)

    assert {:ok, game, _db, [0]} =
             Analysis.play(game, db, [], e4)

    assert length(Node.children(Game.root(game))) == 1
  end

  test "loads a stored game, continues the analysis and saves the new revision" do
    {game, db} = new_game()
    {:ok, store} = Memory.start_link()

    assert {:ok, 1} = Memory.insert(store, game)

    assert {:ok, loaded_game, 1} =
             Memory.get(store, "game-1")

    assert {:ok, continued_game, db, [0]} =
             Analysis.play(
               loaded_game,
               db,
               [],
               move("e2", "e4")
             )

    assert {:ok, 2} =
             Memory.update(store, continued_game, 1)

    assert {:ok, saved_game, 2} =
             Memory.get(store, "game-1")

    child = Game.node_at(saved_game, [0])

    assert %Node{} = child

    assert Node.transition(child) ==
             Transition.move(move("e2", "e4"))

    assert {:ok, position} =
             PositionDB.get(db, Node.position_id(child))

    assert Position.piece_at(
             position,
             Square.from_algebraic("e4")
           ) == {:white, :pawn}

    assert position.side_to_move == :black
  end
end
