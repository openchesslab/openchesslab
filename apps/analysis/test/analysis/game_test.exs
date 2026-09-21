defmodule Analysis.GameTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.Node
  alias Chess.Move
  alias Chess.Square

  describe "new/1" do
    test "creates a game with the initial position as root" do
      game = Game.new(42)

      assert %Node{} = game.root
      assert game.root.position_id == 42
      assert game.root.move == nil
      assert game.root.children == []
    end

    test "starts with empty metadata" do
      game = Game.new(42)

      assert game.metadata == %{}
    end
  end

  describe "new/2" do
    test "stores metadata" do
      metadata = %{
        event: "World Championship",
        site: "Amsterdam",
        round: "1"
      }

      game = Game.new(42, metadata)

      assert game.metadata == metadata
    end

    test "creates the initial position as root" do
      game = Game.new(42, %{event: "World Championship"})

      assert game.root.position_id == 42
      assert game.root.move == nil
      assert game.root.children == []
    end
  end

  describe "root/1" do
    test "returns the root node" do
      game = Game.new(42)

      assert Game.root(game) == game.root
    end
  end

  describe "node_at/2" do
    test "returns the root for an empty path" do
      game = Game.new(42)

      assert Game.node_at(game, []) == game.root
    end

    test "returns a child by path" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      child = Node.new(43, move)

      root = %Node{
        position_id: 42,
        children: [child]
      }

      game = %Game{
        root: root,
        metadata: %{}
      }

      assert Game.node_at(game, [0]) == child
    end

    test "returns a deeply nested node by path" do
      move_1 = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      move_2 = Move.new(Square.from_algebraic("e7"), Square.from_algebraic("e5"))

      grandchild = Node.new(44, move_2)

      child = %Node{
        position_id: 43,
        move: move_1,
        children: [grandchild]
      }

      root = %Node{
        position_id: 42,
        children: [child]
      }

      game = %Game{
        root: root,
        metadata: %{}
      }

      assert Game.node_at(game, [0, 0]) == grandchild
    end

    test "returns nil for a path that does not exist" do
      game = Game.new(42)

      assert Game.node_at(game, [0]) == nil
    end

    test "returns nil when a path becomes invalid halfway through" do
      child = Node.new(43)

      root = %Node{
        position_id: 42,
        children: [child]
      }

      game = %Game{
        root: root,
        metadata: %{}
      }

      assert Game.node_at(game, [0, 0]) == nil
    end

    test "returns nil for a negative index" do
      game = Game.new(42)

      assert Game.node_at(game, [-1]) == nil
    end
  end

  describe "add_child/4" do
    test "adds a child to the root" do
      game = Game.new(:p0)
      move = move("e2", "e4")

      game = Game.add_child(game, [], move, :p1)

      child = Game.node_at(game, [0])

      assert Node.position_id(child) == :p1
      assert Node.move(child) == move
      assert Node.leaf?(child)
    end

    test "adds a child to a nested node" do
      e4 = move("e2", "e4")
      e5 = move("e7", "e5")

      game =
        Game.new(:p0)
        |> Game.add_child([], e4, :p1)
        |> Game.add_child([0], e5, :p2)

      assert Node.position_id(Game.node_at(game, [0, 0])) == :p2
      assert Node.move(Game.node_at(game, [0, 0])) == e5
    end

    test "additional children become variations" do
      e4 = move("e2", "e4")
      d4 = move("d2", "d4")
      c4 = move("c2", "c4")

      game =
        Game.new(:p0)
        |> Game.add_child([], e4, :p1)
        |> Game.add_child([], d4, :p2)
        |> Game.add_child([], c4, :p3)

      root = Game.root(game)

      assert Enum.map(Node.children(root), &Node.position_id/1) ==
               [:p1, :p2, :p3]

      assert Node.position_id(Node.main_child(root)) == :p1
    end

    test "does not add the same move twice from the same node" do
      e4 = move("e2", "e4")

      game =
        Game.new(:p0)
        |> Game.add_child([], e4, :p1)
        |> Game.add_child([], e4, :p1)

      assert length(Node.children(Game.root(game))) == 1
    end

    test "does not merge nodes with the same position id" do
      e4 = move("e2", "e4")
      d4 = move("d2", "d4")

      game =
        Game.new(:p0)
        |> Game.add_child([], e4, :p1)
        |> Game.add_child([], d4, :p1)

      children = Node.children(Game.root(game))

      assert length(children) == 2
      assert Enum.map(children, &Node.position_id/1) == [:p1, :p1]
    end

    test "preserves existing child order when adding a variation" do
      e4 = move("e2", "e4")
      d4 = move("d2", "d4")
      c4 = move("c2", "c4")

      game =
        Game.new(:p0)
        |> Game.add_child([], e4, :p1)
        |> Game.add_child([], d4, :p2)
        |> Game.add_child([], c4, :p3)

      assert Enum.map(Node.children(Game.root(game)), &Node.move/1) ==
               [e4, d4, c4]
    end

    test "returns the game unchanged for a nonexistent path" do
      game = Game.new(:p0)
      move = move("e2", "e4")

      assert Game.add_child(game, [0], move, :p1) == game
    end
  end

  defp move(from, to) do
    Chess.Move.new(
      Chess.Square.from_algebraic(from),
      Chess.Square.from_algebraic(to)
    )
  end
end
