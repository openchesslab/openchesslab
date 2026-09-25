defmodule AnalysisTest do
  use ExUnit.Case, async: true

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore.Memory
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft
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

  defp new_analysis do
    position = Position.starting_position()
    db = new_db()

    {db, position_id} = PositionDB.append(db, position)

    {AnalysisModel.new("analysis-1", position_id), db}
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  test "plays a move and adds the resulting position to the game tree" do
    {analysis, db} = new_analysis()

    e4 = move("e2", "e4")

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], e4)

    child = AnalysisModel.node_at(analysis, [0])

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
    {analysis, db} = new_analysis()

    e4 = move("e2", "e4")
    e5 = move("e7", "e5")

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], e4)

    assert {:ok, analysis, db, [0, 0]} =
             Analysis.play(analysis, db, [0], e5)

    e4_node = AnalysisModel.node_at(analysis, [0])
    e5_node = AnalysisModel.node_at(analysis, [0, 0])

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
    {analysis, db} = new_analysis()

    e4 = move("e2", "e4")
    d4 = move("d2", "d4")

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], e4)

    assert {:ok, analysis, _db, [1]} =
             Analysis.play(analysis, db, [], d4)

    children = analysis |> AnalysisModel.root() |> Node.children()

    assert Enum.map(children, &Node.transition/1) ==
             [Transition.move(e4), Transition.move(d4)]

    assert AnalysisModel.node_at(analysis, [0]) != nil
    assert AnalysisModel.node_at(analysis, [1]) != nil
  end

  test "returns an error for an illegal move" do
    {analysis, db} = new_analysis()

    illegal_move = move("e2", "e5")

    assert Analysis.play(analysis, db, [], illegal_move) ==
             {:error, :illegal_move}

    assert Node.children(AnalysisModel.root(analysis)) == []
  end

  test "returns an error for a nonexistent path" do
    {analysis, db} = new_analysis()

    assert Analysis.play(analysis, db, [0], move("e2", "e4")) ==
             {:error, :node_not_found}
  end

  test "returns an error when the node position does not exist in PositionDB" do
    db = new_db()
    analysis = AnalysisModel.new("analysis-1", 999)

    assert Analysis.play(analysis, db, [], move("e2", "e4")) ==
             {:error, :position_not_found}
  end

  test "reuses an existing PositionDB position reached through a transposition" do
    {analysis, db} = new_analysis()

    # First move order:
    # 1. Nf3 Nf6 2. g3 g6

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], move("g1", "f3"))

    assert {:ok, analysis, db, [0, 0]} =
             Analysis.play(analysis, db, [0], move("g8", "f6"))

    assert {:ok, analysis, db, [0, 0, 0]} =
             Analysis.play(analysis, db, [0, 0], move("g2", "g3"))

    assert {:ok, analysis, db, [0, 0, 0, 0]} =
             Analysis.play(analysis, db, [0, 0, 0], move("g7", "g6"))

    first_node = AnalysisModel.node_at(analysis, [0, 0, 0, 0])
    first_position_id = Node.position_id(first_node)

    # Second move order:
    # 1. g3 g6 2. Nf3 Nf6

    assert {:ok, analysis, db, [1]} =
             Analysis.play(analysis, db, [], move("g2", "g3"))

    assert {:ok, analysis, db, [1, 0]} =
             Analysis.play(analysis, db, [1], move("g7", "g6"))

    assert {:ok, analysis, db, [1, 0, 0]} =
             Analysis.play(analysis, db, [1, 0], move("g1", "f3"))

    assert {:ok, analysis, _db, [1, 0, 0, 0]} =
             Analysis.play(analysis, db, [1, 0, 0], move("g8", "f6"))

    second_node = AnalysisModel.node_at(analysis, [1, 0, 0, 0])
    second_position_id = Node.position_id(second_node)

    assert first_node != second_node
    assert first_position_id == second_position_id
  end

  test "returns the path of the newly created occurrence" do
    {analysis, db} = new_analysis()

    assert {:ok, analysis, _db, [0]} =
             Analysis.play(analysis, db, [], move("e2", "e4"))

    assert AnalysisModel.node_at(analysis, [0]) != nil
  end

  test "returns the path of a nested occurrence" do
    {analysis, db} = new_analysis()

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], move("e2", "e4"))

    assert {:ok, analysis, _db, [0, 0]} =
             Analysis.play(analysis, db, [0], move("e7", "e5"))

    assert AnalysisModel.node_at(analysis, [0, 0]) != nil
  end

  test "playing an existing move returns its existing path" do
    {analysis, db} = new_analysis()
    e4 = move("e2", "e4")

    assert {:ok, analysis, db, [0]} =
             Analysis.play(analysis, db, [], e4)

    assert {:ok, analysis, _db, [0]} =
             Analysis.play(analysis, db, [], e4)

    assert length(Node.children(AnalysisModel.root(analysis))) == 1
  end

  describe "edit/4" do
    test "adds a valid edited position to the game tree" do
      {analysis, db} = new_analysis()

      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("a2"))

      assert {:ok, analysis, db, [0]} =
               Analysis.edit(analysis, db, [], draft)

      child = AnalysisModel.node_at(analysis, [0])

      assert %Node{} = child
      assert Node.transition(child) == Transition.edit()

      assert {:ok, position} =
               PositionDB.get(db, Node.position_id(child))

      assert Position.piece_at(
               position,
               Square.from_algebraic("a2")
             ) == nil
    end

    test "different edits from the same occurrence create separate children" do
      {analysis, db} = new_analysis()

      a2_removed =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("a2"))

      h2_removed =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("h2"))

      assert {:ok, analysis, db, [0]} =
               Analysis.edit(analysis, db, [], a2_removed)

      assert {:ok, analysis, _db, [1]} =
               Analysis.edit(analysis, db, [], h2_removed)

      children =
        analysis
        |> AnalysisModel.root()
        |> Node.children()

      assert length(children) == 2

      assert Enum.map(children, &Node.transition/1) ==
               [Transition.edit(), Transition.edit()]

      assert Node.position_id(Enum.at(children, 0)) !=
               Node.position_id(Enum.at(children, 1))
    end

    test "reuses an existing occurrence for the same edit result" do
      {analysis, db} = new_analysis()

      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("a2"))

      assert {:ok, analysis, db, [0]} =
               Analysis.edit(analysis, db, [], draft)

      assert {:ok, analysis, _db, [0]} =
               Analysis.edit(analysis, db, [], draft)

      assert length(Node.children(AnalysisModel.root(analysis))) == 1
    end

    test "rejects an invalid draft without changing the analysis or database" do
      {analysis, db} = new_analysis()

      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("e1"))

      assert {:error, {:invalid_position, reasons}} =
               Analysis.edit(analysis, db, [], draft)

      assert :invalid_white_king_count in reasons
      assert Node.children(AnalysisModel.root(analysis)) == []

      root_position_id =
        analysis
        |> AnalysisModel.root()
        |> Node.position_id()

      assert {:ok, position} =
               PositionDB.get(db, root_position_id)

      assert Position.piece_at(
               position,
               Square.from_algebraic("e1")
             ) == {:white, :king}
    end

    test "returns an error for a nonexistent path" do
      {analysis, db} = new_analysis()

      draft =
        Position.starting_position()
        |> PositionDraft.new()
        |> PositionDraft.remove_piece(Square.from_algebraic("a2"))

      assert Analysis.edit(analysis, db, [0], draft) ==
               {:error, :node_not_found}
    end
  end

  test "loads a stored analysis, continues the analysis and saves the new revision" do
    {analysis, db} = new_analysis()
    {:ok, store} = Memory.start_link()

    assert {:ok, 1} = Memory.insert(store, analysis)

    assert {:ok, loaded_analysis, 1} =
             Memory.get(store, "analysis-1")

    assert {:ok, continued_analysis, db, [0]} =
             Analysis.play(
               loaded_analysis,
               db,
               [],
               move("e2", "e4")
             )

    assert {:ok, 2} =
             Memory.update(store, continued_analysis, 1)

    assert {:ok, saved_analysis, 2} =
             Memory.get(store, "analysis-1")

    child = AnalysisModel.node_at(saved_analysis, [0])

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
