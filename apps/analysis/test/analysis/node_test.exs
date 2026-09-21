defmodule Analysis.NodeTest do
  use ExUnit.Case, async: true

  alias Analysis.Node
  alias Chess.Move
  alias Chess.Square

  describe "new/1" do
    test "creates a root node" do
      node = Node.new(42)

      assert node.position_id == 42
      assert node.move == nil
      assert node.children == []
    end
  end

  describe "new/2" do
    test "stores the position id and move" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      node = Node.new(43, move)

      assert node.position_id == 43
      assert node.move == move
      assert node.children == []
    end
  end

  describe "position_id/1" do
    test "returns the position id" do
      assert Node.position_id(Node.new(42)) == 42
    end
  end

  describe "move/1" do
    test "returns nil for the root node" do
      assert Node.move(Node.new(42)) == nil
    end

    test "returns the move leading to the node" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      node = Node.new(43, move)

      assert Node.move(node) == move
    end
  end

  describe "children/1" do
    test "returns the children in order" do
      child_1 = Node.new(43)
      child_2 = Node.new(44)

      node = %Node{
        position_id: 42,
        children: [child_1, child_2]
      }

      assert Node.children(node) == [child_1, child_2]
    end
  end

  describe "leaf?/1" do
    test "returns true for a node without children" do
      assert Node.leaf?(Node.new(42))
    end

    test "returns false for a node with children" do
      node = %Node{
        position_id: 42,
        children: [Node.new(43)]
      }

      refute Node.leaf?(node)
    end
  end

  describe "main_child/1" do
    test "returns the first child" do
      child_1 = Node.new(43)
      child_2 = Node.new(44)

      node = %Node{
        position_id: 42,
        children: [child_1, child_2]
      }

      assert Node.main_child(node) == child_1
    end

    test "returns nil when there are no children" do
      assert Node.main_child(Node.new(42)) == nil
    end
  end

  describe "child_index/2" do
    test "returns the index of the child reached by a move" do
      e4 = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      d4 = Move.new(Square.from_algebraic("d2"), Square.from_algebraic("d4"))

      node = %Node{
        position_id: 42,
        children: [
          Node.new(43, e4),
          Node.new(44, d4)
        ]
      }

      assert Node.child_index(node, e4) == 0
      assert Node.child_index(node, d4) == 1
    end

    test "returns nil when the move is not a child" do
      e4 = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      d4 = Move.new(Square.from_algebraic("d2"), Square.from_algebraic("d4"))

      node = %Node{
        position_id: 42,
        children: [Node.new(43, e4)]
      }

      assert Node.child_index(node, d4) == nil
    end
  end
end
