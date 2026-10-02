defmodule Analysis.AnalysesTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft
  alias Chess.Square

  defp analysis_with_variations(analysis_id) do
    analysis_id
    |> AnalysisModel.new(1)
    |> AnalysisModel.add_child([], transition("e2", "e4"), 2)
    |> AnalysisModel.add_child([], transition("d2", "d4"), 3)
    |> AnalysisModel.add_child([], transition("c2", "c4"), 4)
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
    analysis_id = "analysis-#{System.unique_integer([:positive])}"

    %{analysis_id: analysis_id}
  end

  describe "create/1" do
    test "creates an analysis from the standard starting position", %{
      analysis_id: analysis_id
    } do
      assert {:ok, analysis, 1} = Analyses.create(analysis_id)

      assert analysis.id == analysis_id
      assert AnalysisModel.start(analysis) == GameStart.standard()

      root = AnalysisModel.root(analysis)

      assert {:ok, position} =
               PositionStore.get(Node.position_id(root))

      assert position == Position.starting_position()

      assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
    end

    test "does not create the same analysis twice", %{
      analysis_id: analysis_id
    } do
      assert {:ok, _analysis, 1} = Analyses.create(analysis_id)

      assert {:error, :already_exists} =
               Analyses.create(analysis_id)
    end
  end

  describe "create/2 with a setup position" do
    test "roots the analysis at the supplied position", %{
      analysis_id: analysis_id
    } do
      position =
        Position.new()
        |> Position.put_piece(
          Square.from_algebraic("e1"),
          {:white, :king}
        )
        |> Position.put_piece(
          Square.from_algebraic("h8"),
          {:black, :king}
        )

      assert {:ok, analysis, 1} =
               Analyses.create(
                 analysis_id,
                 position: position
               )

      root =
        AnalysisModel.root(analysis)

      assert {:ok, ^position} =
               PositionStore.get(Node.position_id(root))

      assert {:ok, ^analysis, 1} =
               Analyses.get(analysis_id)
    end

    test "rejects an invalid setup position", %{
      analysis_id: analysis_id
    } do
      position = Position.put_piece(Position.new(), Square.from_algebraic("e1"), {:white, :king})

      assert {:error, {:invalid_position, reasons}} =
               Analyses.create(
                 analysis_id,
                 position: position
               )

      assert :invalid_black_king_count in reasons

      assert :not_found =
               Analyses.get(analysis_id)
    end
  end

  describe "create_from_game_record/2" do
    test "creates an analysis containing the canonical main line", %{
      analysis_id: analysis_id
    } do
      initial_position_id =
        PositionStore.append(Position.starting_position())

      e4 =
        move(
          "e2",
          "e4"
        )

      e5 =
        move(
          "e7",
          "e5"
        )

      content =
        GameContent.new(
          initial_position_id,
          [e4, e5]
        )

      record_id =
        "record-#{analysis_id}"

      assert {:ok, record} =
               GameRecords.create(
                 record_id,
                 content,
                 GameStart.standard(),
                 %{
                   "white" => "White",
                   "black" => "Black"
                 }
               )

      assert {:ok, analysis, 1} =
               Analyses.create_from_game_record(
                 analysis_id,
                 record_id
               )

      assert AnalysisModel.source_game_record_id(analysis) ==
               GameRecord.id(record)

      assert AnalysisModel.start(analysis) ==
               GameStart.standard()

      assert Node.position_id(AnalysisModel.root(analysis)) ==
               initial_position_id

      assert Node.transition(
               AnalysisModel.node_at(
                 analysis,
                 [0]
               )
             ) ==
               Transition.move(e4)

      assert Node.transition(
               AnalysisModel.node_at(
                 analysis,
                 [0, 0]
               )
             ) ==
               Transition.move(e5)

      assert analysis.metadata == %{}

      assert {:ok, ^analysis, 1} =
               Analyses.get(analysis_id)
    end

    test "preserves the played game start context", %{
      analysis_id: analysis_id
    } do
      initial_position_id =
        PositionStore.append(Position.starting_position())

      start =
        GameStart.new(37)

      content =
        GameContent.new(
          initial_position_id,
          [
            move(
              "e2",
              "e4"
            )
          ]
        )

      record_id =
        "record-#{analysis_id}"

      assert {:ok, _record} =
               GameRecords.create(
                 record_id,
                 content,
                 start,
                 %{}
               )

      assert {:ok, analysis, 1} =
               Analyses.create_from_game_record(
                 analysis_id,
                 record_id
               )

      assert AnalysisModel.start(analysis) ==
               start
    end

    test "rejects an unknown game record", %{
      analysis_id: analysis_id
    } do
      assert Analyses.create_from_game_record(
               analysis_id,
               "missing-record"
             ) ==
               {:error, :game_record_not_found}

      assert Analyses.get(analysis_id) ==
               :not_found
    end
  end

  test "gets a stored analysis", %{analysis_id: analysis_id} do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns not_found for an unknown analysis", %{analysis_id: analysis_id} do
    assert :not_found = Analyses.get(analysis_id)
  end

  test "does not insert the same analysis twice", %{analysis_id: analysis_id} do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)
    assert {:error, :already_exists} = Analyses.insert(analysis)
  end

  test "plays a move and persists the updated analysis", %{analysis_id: analysis_id} do
    position_id = PositionStore.append(Position.starting_position())
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    e4 = move("e2", "e4")

    assert {:ok, updated_analysis, 2, [0]} =
             Analyses.play(analysis_id, [], e4)

    child = AnalysisModel.node_at(updated_analysis, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.move(e4)

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)

    assert {:ok, position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             position,
             Square.from_algebraic("e4")
           ) == {:white, :pawn}

    assert position.side_to_move == :black
  end

  test "returns analysis_not_found for an unknown analysis", %{analysis_id: analysis_id} do
    assert Analyses.play(analysis_id, [], move("e2", "e4")) ==
             {:error, :analysis_not_found}
  end

  test "returns node_not_found for an unknown path", %{analysis_id: analysis_id} do
    position_id = PositionStore.append(Position.starting_position())
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.play(analysis_id, [0], move("e2", "e4")) ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns position_not_found when the node position does not exist", %{
    analysis_id: analysis_id
  } do
    analysis = AnalysisModel.new(analysis_id, 999_999_999)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.play(analysis_id, [], move("e2", "e4")) ==
             {:error, :position_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns illegal_move without updating the analysis", %{analysis_id: analysis_id} do
    position_id = PositionStore.append(Position.starting_position())
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.play(analysis_id, [], move("e2", "e5")) ==
             {:error, :illegal_move}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "playing an existing continuation does not duplicate it", %{
    analysis_id: analysis_id
  } do
    position_id = PositionStore.append(Position.starting_position())
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, _analysis, 2, [0]} =
             Analyses.play(analysis_id, [], move("e2", "e4"))

    assert {:ok, analysis, 3, [0]} =
             Analyses.play(analysis_id, [], move("e2", "e4"))

    assert length(Node.children(AnalysisModel.root(analysis))) == 1
  end

  test "sets a comment and persists the updated analysis", %{analysis_id: analysis_id} do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2} =
             Analyses.set_comment(analysis_id, [], "Interesting position")

    assert Node.comment(AnalysisModel.root(updated_analysis)) ==
             "Interesting position"

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)
  end

  test "sets a comment on a child node", %{analysis_id: analysis_id} do
    position_id = PositionStore.append(Position.starting_position())
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, _analysis, 2, [0]} =
             Analyses.play(analysis_id, [], move("e2", "e4"))

    assert {:ok, updated_analysis, 3} =
             Analyses.set_comment(analysis_id, [0], "King's Pawn")

    assert updated_analysis
           |> AnalysisModel.node_at([0])
           |> Node.comment() == "King's Pawn"

    assert {:ok, ^updated_analysis, 3} = Analyses.get(analysis_id)
  end

  test "removes a comment with nil", %{analysis_id: analysis_id} do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, _analysis, 2} =
             Analyses.set_comment(analysis_id, [], "Temporary")

    assert {:ok, updated_analysis, 3} =
             Analyses.set_comment(analysis_id, [], nil)

    assert Node.comment(AnalysisModel.root(updated_analysis)) == nil
    assert {:ok, ^updated_analysis, 3} = Analyses.get(analysis_id)
  end

  test "sets NAGs and persists the updated analysis", %{
    analysis_id: analysis_id
  } do
    analysis =
      AnalysisModel.new(
        analysis_id,
        42
      )

    assert {:ok, 1} =
             Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2} =
             Analyses.set_nags(
               analysis_id,
               [],
               [1, 5]
             )

    assert Node.nags(AnalysisModel.root(updated_analysis)) == [1, 5]

    assert {:ok, ^updated_analysis, 2} =
             Analyses.get(analysis_id)
  end

  test "rejects invalid NAGs", %{
    analysis_id: analysis_id
  } do
    analysis =
      AnalysisModel.new(
        analysis_id,
        42
      )

    assert {:ok, 1} =
             Analyses.insert(analysis)

    assert Analyses.set_nags(
             analysis_id,
             [],
             [256]
           ) ==
             {:error, :invalid_nags}

    assert Analyses.set_nags(
             analysis_id,
             [3],
             [1]
           ) ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} =
             Analyses.get(analysis_id)
  end

  test "returns analysis_not_found when setting NAGs on an unknown analysis", %{
    analysis_id: analysis_id
  } do
    assert Analyses.set_nags(
             analysis_id,
             [],
             [1]
           ) ==
             {:error, :analysis_not_found}
  end

  test "returns analysis_not_found when setting a comment on an unknown analysis", %{
    analysis_id: analysis_id
  } do
    assert Analyses.set_comment(analysis_id, [], "Comment") ==
             {:error, :analysis_not_found}
  end

  test "returns node_not_found when setting a comment on an unknown path", %{
    analysis_id: analysis_id
  } do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.set_comment(analysis_id, [0], "Comment") ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "publishes an analysis change after setting a comment", %{
    analysis_id: analysis_id
  } do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    :ok = Analysis.AnalysisEvents.subscribe(analysis_id)

    assert {:ok, _analysis, 2} =
             Analyses.set_comment(analysis_id, [], "Comment")

    assert_receive {:analysis_changed, ^analysis_id}
  end

  test "does not publish an analysis change when setting a comment fails", %{
    analysis_id: analysis_id
  } do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    :ok = Analysis.AnalysisEvents.subscribe(analysis_id)

    assert Analyses.set_comment(analysis_id, [0], "Comment") ==
             {:error, :node_not_found}

    refute_receive {:analysis_changed, ^analysis_id}
  end

  test "promotes a variation and persists the updated analysis", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2, [0]} =
             Analyses.promote(analysis_id, [1])

    assert updated_analysis
           |> AnalysisModel.node_at([0])
           |> Node.transition() == transition("d2", "d4")

    assert updated_analysis
           |> AnalysisModel.node_at([1])
           |> Node.transition() == transition("e2", "e4")

    assert updated_analysis
           |> AnalysisModel.node_at([2])
           |> Node.transition() == transition("c2", "c4")

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)
  end

  test "promotes a nested variation and returns its new path", %{
    analysis_id: analysis_id
  } do
    analysis =
      analysis_id
      |> AnalysisModel.new(1)
      |> AnalysisModel.add_child([], transition("e2", "e4"), 2)
      |> AnalysisModel.add_child([0], transition("e7", "e5"), 3)
      |> AnalysisModel.add_child([0], transition("c7", "c5"), 4)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2, [0, 0]} =
             Analyses.promote(analysis_id, [0, 1])

    assert updated_analysis
           |> AnalysisModel.node_at([0, 0])
           |> Node.transition() == transition("c7", "c5")

    assert updated_analysis
           |> AnalysisModel.node_at([0, 1])
           |> Node.transition() == transition("e7", "e5")
  end

  test "returns analysis_not_found when promoting in an unknown analysis", %{
    analysis_id: analysis_id
  } do
    assert Analyses.promote(analysis_id, [0]) ==
             {:error, :analysis_not_found}
  end

  test "returns root when promoting the root", %{analysis_id: analysis_id} do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.promote(analysis_id, []) ==
             {:error, :root}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns node_not_found when promoting an unknown path", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.promote(analysis_id, [99]) ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "publishes an analysis change after promoting a variation", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    :ok = Analysis.AnalysisEvents.subscribe(analysis_id)

    assert {:ok, _analysis, 2, [0]} =
             Analyses.promote(analysis_id, [1])

    assert_receive {:analysis_changed, ^analysis_id}
  end

  test "removes a variation and persists the updated analysis", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2, []} =
             Analyses.remove(analysis_id, [1])

    assert updated_analysis
           |> AnalysisModel.node_at([0])
           |> Node.transition() == transition("e2", "e4")

    assert updated_analysis
           |> AnalysisModel.node_at([1])
           |> Node.transition() == transition("c2", "c4")

    assert AnalysisModel.node_at(updated_analysis, [2]) == nil

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)
  end

  test "removes a nested variation subtree and returns its parent path", %{
    analysis_id: analysis_id
  } do
    analysis =
      analysis_id
      |> AnalysisModel.new(1)
      |> AnalysisModel.add_child([], transition("e2", "e4"), 2)
      |> AnalysisModel.add_child([0], transition("e7", "e5"), 3)
      |> AnalysisModel.add_child([0, 0], transition("g1", "f3"), 4)
      |> AnalysisModel.add_child([0], transition("c7", "c5"), 5)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {:ok, updated_analysis, 2, [0]} =
             Analyses.remove(analysis_id, [0, 0])

    assert updated_analysis
           |> AnalysisModel.node_at([0, 0])
           |> Node.transition() == transition("c7", "c5")

    assert AnalysisModel.node_at(updated_analysis, [0, 0, 0]) == nil

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)
  end

  test "returns analysis_not_found when removing from an unknown analysis", %{
    analysis_id: analysis_id
  } do
    assert Analyses.remove(analysis_id, [0]) ==
             {:error, :analysis_not_found}
  end

  test "returns root when removing the root", %{analysis_id: analysis_id} do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.remove(analysis_id, []) ==
             {:error, :root}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns node_not_found when removing an unknown path", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert Analyses.remove(analysis_id, [99]) ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "publishes an analysis change after removing a variation", %{
    analysis_id: analysis_id
  } do
    analysis = analysis_with_variations(analysis_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    :ok = Analysis.AnalysisEvents.subscribe(analysis_id)

    assert {:ok, _analysis, 2, []} =
             Analyses.remove(analysis_id, [1])

    assert_receive {:analysis_changed, ^analysis_id}
  end

  test "edits a position and persists the updated analysis", %{
    analysis_id: analysis_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.remove_piece(Square.from_algebraic("e2"))

    assert {:ok, updated_analysis, 2, [0]} =
             Analyses.edit(analysis_id, [], draft)

    child = AnalysisModel.node_at(updated_analysis, [0])

    assert %Node{} = child
    assert Node.transition(child) == Transition.edit()

    assert {:ok, ^updated_analysis, 2} = Analyses.get(analysis_id)

    assert {:ok, edited_position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             edited_position,
             Square.from_algebraic("e2")
           ) == nil
  end

  test "returns analysis_not_found when editing an unknown analysis", %{
    analysis_id: analysis_id
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

    assert Analyses.edit(analysis_id, [], draft) ==
             {:error, :analysis_not_found}
  end

  test "returns node_not_found when editing an unknown path", %{
    analysis_id: analysis_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

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

    assert Analyses.edit(analysis_id, [0], draft) ==
             {:error, :node_not_found}

    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "returns invalid_position without updating the analysis", %{
    analysis_id: analysis_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.remove_piece(Square.from_algebraic("e1"))

    assert {:error, {:invalid_position, reasons}} =
             Analyses.edit(analysis_id, [], draft)

    assert reasons != []
    assert {:ok, ^analysis, 1} = Analyses.get(analysis_id)
  end

  test "editing the same position does not duplicate the continuation", %{
    analysis_id: analysis_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

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

    assert {:ok, _analysis, 2, [0]} =
             Analyses.edit(analysis_id, [], draft)

    assert {:ok, updated_analysis, 3, [0]} =
             Analyses.edit(analysis_id, [], draft)

    assert length(Node.children(AnalysisModel.root(updated_analysis))) == 1
  end

  test "publishes an analysis change after editing a position", %{
    analysis_id: analysis_id
  } do
    position = Position.starting_position()
    position_id = PositionStore.append(position)
    analysis = AnalysisModel.new(analysis_id, position_id)

    assert {:ok, 1} = Analyses.insert(analysis)

    :ok = Analysis.AnalysisEvents.subscribe(analysis_id)

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

    assert {:ok, _analysis, 2, [0]} =
             Analyses.edit(analysis_id, [], draft)

    assert_receive {:analysis_changed, ^analysis_id}
  end

  test "lists stored analyses", %{analysis_id: analysis_id} do
    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 1} = Analyses.insert(analysis)

    assert {analysis, 1} in Analyses.list()
  end
end
