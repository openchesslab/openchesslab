defmodule Analysis.NodeTest do
  use ExUnit.Case, async: true

  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Square

  describe "new/1" do
    test "creates a root node" do
      node = Node.new(42)

      assert node.position_id == 42
      assert node.transition == nil
      assert node.children == []
    end
  end

  describe "new/2" do
    test "stores the position id and transition" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      transition = Transition.move(move)

      node = Node.new(43, transition)

      assert node.position_id == 43
      assert node.transition == transition
      assert node.children == []
    end
  end

  describe "position_id/1" do
    test "returns the position id" do
      assert Node.position_id(Node.new(42)) == 42
    end
  end

  describe "transition/1" do
    test "returns nil for the root node" do
      assert Node.transition(Node.new(42)) == nil
    end

    test "returns the transition leading to the node" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      transition = Transition.move(move)
      node = Node.new(43, transition)

      assert Node.transition(node) == transition
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

  describe "child_index/3" do
    test "returns the index of the child reached by a transition" do
      e4 =
        Transition.move(
          Move.new(
            Square.from_algebraic("e2"),
            Square.from_algebraic("e4")
          )
        )

      d4 =
        Transition.move(
          Move.new(
            Square.from_algebraic("d2"),
            Square.from_algebraic("d4")
          )
        )

      node = %Node{
        position_id: 42,
        children: [
          Node.new(43, e4),
          Node.new(44, d4)
        ]
      }

      assert Node.child_index(node, e4, 43) == 0
      assert Node.child_index(node, d4, 44) == 1
    end

    test "returns nil when the transition is not a child" do
      e4 =
        Transition.move(
          Move.new(
            Square.from_algebraic("e2"),
            Square.from_algebraic("e4")
          )
        )

      d4 =
        Transition.move(
          Move.new(
            Square.from_algebraic("d2"),
            Square.from_algebraic("d4")
          )
        )

      node = %Node{
        position_id: 42,
        children: [Node.new(43, e4)]
      }

      assert Node.child_index(node, d4, 44) == nil
    end

    test "distinguishes children by transition and position id" do
      transition =
        Transition.move(
          Move.new(
            Square.from_algebraic("e2"),
            Square.from_algebraic("e4")
          )
        )

      node = %Node{
        position_id: 42,
        children: [
          Node.new(43, transition),
          Node.new(44, transition)
        ]
      }

      assert Node.child_index(node, transition, 43) == 0
      assert Node.child_index(node, transition, 44) == 1
      assert Node.child_index(node, transition, 45) == nil
    end
  end

  describe "comment/1" do
    test "returns nil by default" do
      assert Node.comment(Node.new(42)) == nil
    end

    test "returns the node comment" do
      node = %Node{
        position_id: 42,
        comment: "An interesting position"
      }

      assert Node.comment(node) == "An interesting position"
    end
  end

  describe "Jason.Encoder" do
    test "encodes a root node with transition: null" do
      node = Node.new(42, nil)

      decoded = Jason.decode!(Jason.encode!(node))

      assert decoded["position_id"] == 42
      assert decoded["transition"] == nil
      assert decoded["comment"] == nil
      assert decoded["children"] == []
    end

    test "encodes a {:move, _} transition as a flat move object" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))
      node = Node.new(43, Transition.move(move))

      decoded = Jason.decode!(Jason.encode!(node))

      assert decoded["transition"] == %{
               "type" => "move",
               "from" => 12,
               "to" => 28,
               "promotion" => nil
             }
    end

    test "encodes a promotion move with the promotion as a string" do
      move = Move.new(Square.from_algebraic("e7"), Square.from_algebraic("e8"), :queen)
      node = Node.new(99, Transition.move(move))

      decoded = Jason.decode!(Jason.encode!(node))

      assert decoded["transition"] == %{
               "type" => "move",
               "from" => 52,
               "to" => 60,
               "promotion" => "queen"
             }
    end

    test "encodes an :edit transition as {type: 'edit'}" do
      node = Node.new(7, :edit)

      decoded = Jason.decode!(Jason.encode!(node))

      assert decoded["transition"] == %{"type" => "edit"}
    end

    test "encodes children recursively" do
      e4_transition =
        Transition.move(Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4")))

      d4_transition =
        Transition.move(Move.new(Square.from_algebraic("d2"), Square.from_algebraic("d4")))

      node = %Node{
        position_id: 1,
        children: [
          %Node{position_id: 2, transition: e4_transition},
          %Node{position_id: 3, transition: d4_transition}
        ]
      }

      decoded = Jason.decode!(Jason.encode!(node))

      assert decoded["children"] == [
               %{
                 "position_id" => 2,
                 "transition" => %{
                   "type" => "move",
                   "from" => 12,
                   "to" => 28,
                   "promotion" => nil
                 },
                 "comment" => nil,
                 "children" => []
               },
               %{
                 "position_id" => 3,
                 "transition" => %{
                   "type" => "move",
                   "from" => 11,
                   "to" => 27,
                   "promotion" => nil
                 },
                 "comment" => nil,
                 "children" => []
               }
             ]
    end
  end

  describe "nags" do
    test "defaults to none" do
      assert Node.nags(Node.new(1)) == []
    end

    test "accepts PGN NAGs, deduplicated" do
      assert {:ok, node} = Node.set_nags(Node.new(1), [1, 5, 1])
      assert Node.nags(node) == [1, 5]
    end

    test "rejects values outside 0..255 and non-integers" do
      assert Node.set_nags(Node.new(1), [256]) == {:error, :invalid_nags}
      assert Node.set_nags(Node.new(1), [-1]) == {:error, :invalid_nags}
      assert Node.set_nags(Node.new(1), ["1"]) == {:error, :invalid_nags}
    end

    test "caps how many NAGs a node keeps" do
      assert Node.set_nags(Node.new(1), Enum.to_list(1..8)) |> elem(0) == :ok
      assert Node.set_nags(Node.new(1), Enum.to_list(1..9)) == {:error, :invalid_nags}
    end

    test "valid_nags?/1 is the shared check" do
      assert Node.valid_nags?([])
      assert Node.valid_nags?([0, 255])
      refute Node.valid_nags?([256])
      refute Node.valid_nags?("1")
    end
  end
end
