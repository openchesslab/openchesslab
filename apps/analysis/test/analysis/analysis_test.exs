defmodule Analysis.AnalysisTest do
  use ExUnit.Case, async: true

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.GameStart
  alias Analysis.MoveContext
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Square

  describe "new/4" do
    test "stores an explicit game start context" do
      start = GameStart.new(37)

      analysis =
        AnalysisModel.new(
          "analysis-1",
          42,
          start,
          %{event: "Analysis"}
        )

      assert AnalysisModel.start(analysis) == start
      assert GameStart.fullmove_number(AnalysisModel.start(analysis)) == 37
      assert analysis.metadata == %{event: "Analysis"}
    end
  end

  describe "source game" do
    test "has no source game by default" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.source_game_id(analysis) == nil
    end

    test "stores the canonical game it was created from" do
      analysis =
        AnalysisModel.new(
          "analysis-1",
          42,
          "game-1",
          GameStart.standard(),
          %{title: "My analysis"}
        )

      assert AnalysisModel.source_game_id(analysis) == "game-1"
      assert AnalysisModel.root(analysis).position_id == 42
      assert analysis.metadata == %{title: "My analysis"}
    end
  end

  describe "new/2" do
    test "creates an analysis with the initial position as root" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert analysis.id == "analysis-1"
      assert %Node{} = analysis.root
      assert analysis.root.position_id == 42
      assert analysis.root.transition == nil
      assert analysis.root.children == []
      assert GameStart.fullmove_number(AnalysisModel.start(analysis)) == 1
    end

    test "starts with empty metadata" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert analysis.metadata == %{}
    end
  end

  describe "new/3" do
    test "stores metadata" do
      metadata = %{
        event: "World Championship",
        site: "Amsterdam",
        round: "1"
      }

      analysis = AnalysisModel.new("analysis-1", 42, metadata)

      assert analysis.metadata == metadata
    end

    test "creates the initial position as root" do
      analysis =
        AnalysisModel.new(
          "analysis-1",
          42,
          %{event: "World Championship"}
        )

      assert analysis.root.position_id == 42
      assert analysis.root.transition == nil
      assert analysis.root.children == []
    end

    test "creates an analysis with an explicit identity" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert analysis.id == "analysis-1"
      assert analysis.root.position_id == 42
      assert analysis.root.transition == nil
      assert analysis.root.children == []
      assert analysis.metadata == %{}
    end
  end

  describe "root/1" do
    test "returns the root node" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.root(analysis) == analysis.root
    end
  end

  describe "node_at/2" do
    test "returns the root for an empty path" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.node_at(analysis, []) == analysis.root
    end

    test "returns a child by path" do
      transition = transition("e2", "e4")
      child = Node.new(43, transition)

      root = %Node{
        position_id: 42,
        children: [child]
      }

      analysis = %AnalysisModel{
        id: "analysis-1",
        root: root,
        start: GameStart.standard(),
        metadata: %{}
      }

      assert AnalysisModel.node_at(analysis, [0]) == child
    end

    test "returns a deeply nested node by path" do
      transition_1 = transition("e2", "e4")
      transition_2 = transition("e7", "e5")

      grandchild = Node.new(44, transition_2)

      child = %Node{
        position_id: 43,
        transition: transition_1,
        children: [grandchild]
      }

      root = %Node{
        position_id: 42,
        children: [child]
      }

      analysis = %AnalysisModel{
        id: "analysis-1",
        root: root,
        start: GameStart.standard(),
        metadata: %{}
      }

      assert AnalysisModel.node_at(analysis, [0, 0]) == grandchild
    end

    test "returns nil for a path that does not exist" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.node_at(analysis, [0]) == nil
    end

    test "returns nil when a path becomes invalid halfway through" do
      child = Node.new(43)

      root = %Node{
        position_id: 42,
        children: [child]
      }

      analysis = %AnalysisModel{
        id: "analysis-1",
        root: root,
        start: GameStart.standard(),
        metadata: %{}
      }

      assert AnalysisModel.node_at(analysis, [0, 0]) == nil
    end

    test "returns nil for a negative index" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.node_at(analysis, [-1]) == nil
    end
  end

  describe "add_child/4" do
    test "adds a child to the root" do
      analysis = AnalysisModel.new("analysis-1", :p0)
      transition = transition("e2", "e4")

      analysis = AnalysisModel.add_child(analysis, [], transition, :p1)

      child = AnalysisModel.node_at(analysis, [0])

      assert Node.position_id(child) == :p1
      assert Node.transition(child) == transition
      assert Node.leaf?(child)
    end

    test "adds a child to a nested node" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)

      assert Node.position_id(AnalysisModel.node_at(analysis, [0, 0])) == :p2
      assert Node.transition(AnalysisModel.node_at(analysis, [0, 0])) == e5
    end

    test "additional children become variations" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")
      c4 = transition("c2", "c4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], d4, :p2)
        |> AnalysisModel.add_child([], c4, :p3)

      root = AnalysisModel.root(analysis)

      assert Enum.map(Node.children(root), &Node.position_id/1) ==
               [:p1, :p2, :p3]

      assert Node.position_id(Node.main_child(root)) == :p1
    end

    test "does not add the same transition and position twice from the same node" do
      e4 = transition("e2", "e4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], e4, :p1)

      assert length(Node.children(AnalysisModel.root(analysis))) == 1
    end

    test "does not merge children with the same transition and different positions" do
      e4 = transition("e2", "e4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], e4, :p2)

      children = Node.children(AnalysisModel.root(analysis))

      assert length(children) == 2
      assert Enum.map(children, &Node.position_id/1) == [:p1, :p2]
    end

    test "does not merge nodes with the same position id and different transitions" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], d4, :p1)

      children = Node.children(AnalysisModel.root(analysis))

      assert length(children) == 2
      assert Enum.map(children, &Node.position_id/1) == [:p1, :p1]
    end

    test "preserves existing child order when adding a variation" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")
      c4 = transition("c2", "c4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], d4, :p2)
        |> AnalysisModel.add_child([], c4, :p3)

      assert Enum.map(Node.children(AnalysisModel.root(analysis)), &Node.transition/1) ==
               [e4, d4, c4]
    end

    test "returns the analysis unchanged for a nonexistent path" do
      analysis = AnalysisModel.new("analysis-1", :p0)
      transition = transition("e2", "e4")

      assert AnalysisModel.add_child(analysis, [0], transition, :p1) == analysis
    end

    test "adds an edit child" do
      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], Transition.edit(), :p1)

      child = AnalysisModel.node_at(analysis, [0])

      assert Node.position_id(child) == :p1
      assert Node.transition(child) == Transition.edit()
    end

    test "keeps different edit results as separate children" do
      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], Transition.edit(), :p1)
        |> AnalysisModel.add_child([], Transition.edit(), :p2)

      children = Node.children(AnalysisModel.root(analysis))

      assert length(children) == 2

      assert Enum.map(children, &Node.position_id/1) ==
               [:p1, :p2]

      assert Enum.map(children, &Node.transition/1) ==
               [Transition.edit(), Transition.edit()]
    end

    test "does not add the same edit result twice" do
      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], Transition.edit(), :p1)
        |> AnalysisModel.add_child([], Transition.edit(), :p1)

      children = Node.children(AnalysisModel.root(analysis))

      assert length(children) == 1

      assert Node.position_id(hd(children)) == :p1
      assert Node.transition(hd(children)) == Transition.edit()
    end
  end

  describe "promote/2" do
    test "promotes a variation to the main continuation" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")
      e6 = transition("e7", "e6")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)
        |> AnalysisModel.add_child([0], e6, :p4)

      assert {:ok, analysis, [0, 0]} =
               AnalysisModel.promote(analysis, [0, 1])

      node = AnalysisModel.node_at(analysis, [0])

      assert Enum.map(Node.children(node), &Node.transition/1) ==
               [c5, e5, e6]
    end

    test "preserves the subtree of the promoted variation" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")
      nf3 = transition("g1", "f3")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)
        |> AnalysisModel.add_child([0, 1], nf3, :p4)

      assert {:ok, analysis, [0, 0]} =
               AnalysisModel.promote(analysis, [0, 1])

      promoted = AnalysisModel.node_at(analysis, [0, 0])

      assert Node.transition(promoted) == c5
      assert Node.transition(Node.main_child(promoted)) == nf3
    end

    test "leaves the analysis unchanged when the node is already the main continuation" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)

      assert {:ok, promoted_analysis, [0, 0]} =
               AnalysisModel.promote(analysis, [0, 0])

      assert promoted_analysis == analysis
    end

    test "can promote a root variation" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], d4, :p2)

      assert {:ok, analysis, [0]} =
               AnalysisModel.promote(analysis, [1])

      assert Node.transition(AnalysisModel.node_at(analysis, [0])) == d4
      assert Node.transition(AnalysisModel.node_at(analysis, [1])) == e4
    end

    test "returns an error for a nonexistent path" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert AnalysisModel.promote(analysis, [0]) ==
               {:error, :node_not_found}
    end

    test "cannot promote the root" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert AnalysisModel.promote(analysis, []) ==
               {:error, :root}
    end
  end

  describe "remove/2" do
    test "removes a variation" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")
      e6 = transition("e7", "e6")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)
        |> AnalysisModel.add_child([0], e6, :p4)

      assert {:ok, analysis, [0]} =
               AnalysisModel.remove(analysis, [0, 1])

      node = AnalysisModel.node_at(analysis, [0])

      assert Enum.map(Node.children(node), &Node.transition/1) ==
               [e5, e6]
    end

    test "removes the main continuation" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)

      assert {:ok, analysis, [0]} =
               AnalysisModel.remove(analysis, [0, 0])

      node = AnalysisModel.node_at(analysis, [0])

      assert Enum.map(Node.children(node), &Node.transition/1) ==
               [c5]

      assert Node.transition(Node.main_child(node)) == c5
    end

    test "removes the entire subtree" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")
      c5 = transition("c7", "c5")
      nf3 = transition("g1", "f3")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)
        |> AnalysisModel.add_child([0], c5, :p3)
        |> AnalysisModel.add_child([0, 1], nf3, :p4)

      assert AnalysisModel.node_at(analysis, [0, 1, 0]) != nil

      assert {:ok, analysis, [0]} =
               AnalysisModel.remove(analysis, [0, 1])

      assert AnalysisModel.node_at(analysis, [0, 1]) == nil
    end

    test "can remove a root continuation" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([], d4, :p2)

      assert {:ok, analysis, []} =
               AnalysisModel.remove(analysis, [0])

      assert Enum.map(Node.children(AnalysisModel.root(analysis)), &Node.transition/1) ==
               [d4]
    end

    test "returns an error for a nonexistent path" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert AnalysisModel.remove(analysis, [0]) ==
               {:error, :node_not_found}
    end

    test "cannot remove the root" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert AnalysisModel.remove(analysis, []) ==
               {:error, :root}
    end
  end

  describe "reconcile_path/3" do
    test "keeps the path when the occurrence has not moved" do
      old_analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], transition("e2", "e4"), :p1)
        |> AnalysisModel.add_child([0], transition("e7", "e5"), :p2)

      new_analysis =
        AnalysisModel.add_child(
          old_analysis,
          [0, 0],
          transition("g1", "f3"),
          :p3
        )

      assert AnalysisModel.reconcile_path(old_analysis, new_analysis, [0, 0]) ==
               [0, 0]
    end

    test "follows an occurrence when its variation is promoted" do
      old_analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], transition("e2", "e4"), :p1)
        |> AnalysisModel.add_child([0], transition("e7", "e5"), :p2)
        |> AnalysisModel.add_child([0], transition("c7", "c5"), :p3)
        |> AnalysisModel.add_child([0, 1], transition("g1", "f3"), :p4)

      assert {:ok, new_analysis, [0, 0]} =
               AnalysisModel.promote(old_analysis, [0, 1])

      assert AnalysisModel.reconcile_path(old_analysis, new_analysis, [0, 1, 0]) ==
               [0, 0, 0]
    end

    test "falls back to the nearest surviving ancestor after removal" do
      old_analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], transition("e2", "e4"), :p1)
        |> AnalysisModel.add_child([0], transition("e7", "e5"), :p2)
        |> AnalysisModel.add_child([0, 0], transition("g1", "f3"), :p3)
        |> AnalysisModel.add_child([0], transition("c7", "c5"), :p4)

      assert {:ok, new_analysis, [0]} =
               AnalysisModel.remove(old_analysis, [0, 0])

      assert AnalysisModel.reconcile_path(old_analysis, new_analysis, [0, 0, 0]) ==
               [0]
    end

    test "returns the root when the first occurrence no longer exists" do
      old_analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], transition("e2", "e4"), :p1)

      assert {:ok, new_analysis, []} =
               AnalysisModel.remove(old_analysis, [0])

      assert AnalysisModel.reconcile_path(old_analysis, new_analysis, [0]) == []
    end
  end

  describe "set_comment/3" do
    test "sets a comment on the root" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], "Opening analysis")

      assert Node.comment(AnalysisModel.root(analysis)) == "Opening analysis"
    end

    test "sets a comment on a nested occurrence" do
      e4 = transition("e2", "e4")
      e5 = transition("e7", "e5")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :p1)
        |> AnalysisModel.add_child([0], e5, :p2)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [0, 0], "Main line")

      assert Node.comment(AnalysisModel.node_at(analysis, [0, 0])) ==
               "Main line"

      assert Node.comment(AnalysisModel.node_at(analysis, [0])) == nil
    end

    test "comments belong to occurrences rather than positions" do
      e4 = transition("e2", "e4")
      d4 = transition("d2", "d4")

      analysis =
        AnalysisModel.new("analysis-1", :p0)
        |> AnalysisModel.add_child([], e4, :same_position)
        |> AnalysisModel.add_child([], d4, :same_position)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [0], "First occurrence")

      assert Node.comment(AnalysisModel.node_at(analysis, [0])) ==
               "First occurrence"

      assert Node.comment(AnalysisModel.node_at(analysis, [1])) == nil
    end

    test "replaces an existing comment" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], "First comment")

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], "Updated comment")

      assert Node.comment(AnalysisModel.root(analysis)) == "Updated comment"
    end

    test "removes a comment with nil" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], "Comment")

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], nil)

      assert Node.comment(AnalysisModel.root(analysis)) == nil
    end

    test "normalizes an empty comment to nil" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert {:ok, analysis} =
               AnalysisModel.set_comment(analysis, [], "")

      assert Node.comment(AnalysisModel.root(analysis)) == nil
    end

    test "returns an error for a nonexistent path" do
      analysis = AnalysisModel.new("analysis-1", :p0)

      assert AnalysisModel.set_comment(analysis, [0], "Comment") ==
               {:error, :node_not_found}
    end
  end

  describe "move_context/3" do
    test "calculates the context for a move from the root" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.move_context(analysis, :white, []) ==
               %MoveContext{
                 fullmove_number: 1,
                 side: :white
               }
    end

    test "calculates the context from the occurrence path" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.move_context(analysis, :white, [0]) ==
               %MoveContext{
                 fullmove_number: 1,
                 side: :black
               }

      assert AnalysisModel.move_context(analysis, :white, [0, 1]) ==
               %MoveContext{
                 fullmove_number: 2,
                 side: :white
               }
    end

    test "uses the explicit game start context" do
      analysis =
        AnalysisModel.new(
          "analysis-1",
          42,
          GameStart.new(37),
          %{}
        )

      assert AnalysisModel.move_context(analysis, :black, []) ==
               %MoveContext{
                 fullmove_number: 37,
                 side: :black
               }

      assert AnalysisModel.move_context(analysis, :black, [0]) ==
               %MoveContext{
                 fullmove_number: 38,
                 side: :white
               }
    end

    test "variation indexes do not affect the move context" do
      analysis = AnalysisModel.new("analysis-1", 42)

      assert AnalysisModel.move_context(analysis, :white, [0, 0, 0]) ==
               AnalysisModel.move_context(analysis, :white, [0, 1, 0])
    end
  end

  defp transition(from, to) do
    from
    |> move(to)
    |> Transition.move()
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
