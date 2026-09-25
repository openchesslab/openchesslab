defmodule Analysis.AnalysesTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Analyses
  alias Analysis.Game
  alias Analysis.GameStart
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft
  alias Chess.Square

  defmodule FailingPositionStore do
    use GenServer

    def start_link(mode) do
      GenServer.start_link(
        __MODULE__,
        mode,
        name: Analysis.PositionStore.clustered_server()
      )
    end

    @impl true
    def init(mode) do
      {:ok, mode}
    end

    @impl true
    def handle_call(
          {:append, _position},
          _from,
          state
        ) do
      {:reply, {:error, :disk_failure}, state}
    end

    def handle_call(
          {:get, _position_id},
          _from,
          :get_failure = state
        ) do
      {:reply, {:error, :disk_failure}, state}
    end

    def handle_call(
          {:get, _position_id},
          _from,
          state
        ) do
      {:reply, {:ok, Position.starting_position()}, state}
    end
  end

  defp analysis_with_variations(analysis_id) do
    AnalysisModel.new(analysis_id, 1)
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

  defp with_failing_position_store(
         mode,
         fun
       ) do
    :ok =
      Supervisor.terminate_child(
        Analysis.Supervisor,
        PositionStore
      )

    {:ok, pid} =
      FailingPositionStore.start_link(mode)

    try do
      fun.()
    after
      GenServer.stop(pid)

      {:ok, _pid} =
        Supervisor.restart_child(
          Analysis.Supervisor,
          PositionStore
        )
    end
  end

  defmodule RecordingAnalysisStore do
    @behaviour Analysis.AnalysisStore

    def insert(store, analysis) do
      send(self(), {:analysis_store_insert, store, analysis})
      {:ok, 42}
    end

    def get(store, analysis_id) do
      send(self(), {:analysis_store_get, store, analysis_id})
      :not_found
    end

    def list(store) do
      send(self(), {:analysis_store_list, store})
      []
    end

    def update(store, analysis, revision) do
      send(
        self(),
        {:analysis_store_update, store, analysis, revision}
      )

      {:ok, revision + 1}
    end

    def delete(store, analysis_id, revision) do
      send(
        self(),
        {:analysis_store_delete, store, analysis_id, revision}
      )

      :ok
    end
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
      assert AnalysisModel.start(analysis) == Analysis.GameStart.standard()

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

  describe "create_from_game/2" do
    test "creates an analysis containing the canonical main line", %{
      analysis_id: analysis_id
    } do
      initial_position_id =
        PositionStore.append(Position.starting_position())

      e4 = move("e2", "e4")
      e5 = move("e7", "e5")

      game =
        Game.new(
          "game-1",
          initial_position_id,
          [e4, e5],
          %{
            white: "White",
            black: "Black"
          }
        )

      assert {:ok, analysis, 1} =
               Analyses.create_from_game(
                 analysis_id,
                 game
               )

      assert AnalysisModel.source_game_id(analysis) ==
               "game-1"

      assert AnalysisModel.start(analysis) ==
               GameStart.standard()

      assert Node.position_id(AnalysisModel.root(analysis)) == initial_position_id

      assert Node.transition(
               AnalysisModel.node_at(
                 analysis,
                 [0]
               )
             ) == Transition.move(e4)

      assert Node.transition(
               AnalysisModel.node_at(
                 analysis,
                 [0, 0]
               )
             ) == Transition.move(e5)

      assert analysis.metadata == %{}

      assert {:ok, ^analysis, 1} =
               Analyses.get(analysis_id)
    end

    test "preserves the canonical game start context", %{
      analysis_id: analysis_id
    } do
      initial_position_id =
        PositionStore.append(Position.starting_position())

      start = GameStart.new(37)

      game =
        Game.new(
          "game-1",
          initial_position_id,
          start,
          [move("e2", "e4")],
          %{}
        )

      assert {:ok, analysis, 1} =
               Analyses.create_from_game(
                 analysis_id,
                 game
               )

      assert AnalysisModel.start(analysis) == start
    end

    test "rejects a canonical game with an illegal move", %{
      analysis_id: analysis_id
    } do
      initial_position_id =
        PositionStore.append(Position.starting_position())

      game =
        Game.new(
          "game-1",
          initial_position_id,
          [
            move("e2", "e4"),
            move("e7", "e4")
          ]
        )

      assert Analyses.create_from_game(
               analysis_id,
               game
             ) ==
               {:error, {:invalid_game, {:illegal_move, 2}}}

      assert Analyses.get(analysis_id) ==
               :not_found
    end

    test "rejects a game whose initial position is missing", %{
      analysis_id: analysis_id
    } do
      game =
        Game.new(
          "game-1",
          999_999_999
        )

      assert Analyses.create_from_game(
               analysis_id,
               game
             ) ==
               {:error, {:invalid_game, {:position_not_found, 999_999_999}}}

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
      AnalysisModel.new(analysis_id, 1)
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
      AnalysisModel.new(analysis_id, 1)
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

  test "does not create an analysis when storing the initial position fails",
       %{
         analysis_id: analysis_id
       } do
    with_failing_position_store(
      :append_failure,
      fn ->
        assert Analyses.create(analysis_id) ==
                 {:error, {:position_store, :disk_failure}}

        assert Analyses.get(analysis_id) ==
                 :not_found
      end
    )
  end

  test "does not update an analysis when reading its position fails",
       %{
         analysis_id: analysis_id
       } do
    analysis =
      AnalysisModel.new(
        analysis_id,
        1
      )

    assert {:ok, 1} =
             Analyses.insert(analysis)

    with_failing_position_store(
      :get_failure,
      fn ->
        assert Analyses.play(
                 analysis_id,
                 [],
                 move("e2", "e4")
               ) ==
                 {:error, {:position_store, :disk_failure}}

        assert {:ok, ^analysis, 1} =
                 Analyses.get(analysis_id)
      end
    )
  end

  test "does not update an analysis when storing an edited position fails",
       %{
         analysis_id: analysis_id
       } do
    position =
      Position.starting_position()

    analysis =
      AnalysisModel.new(
        analysis_id,
        1
      )

    assert {:ok, 1} =
             Analyses.insert(analysis)

    draft =
      position
      |> PositionDraft.new()
      |> PositionDraft.remove_piece(Square.from_algebraic("e2"))

    with_failing_position_store(
      :append_failure,
      fn ->
        assert Analyses.edit(
                 analysis_id,
                 [],
                 draft
               ) ==
                 {:error, {:position_store, :disk_failure}}

        assert {:ok, ^analysis, 1} =
                 Analyses.get(analysis_id)
      end
    )
  end

  test "uses the configured analysis store adapter", %{
    analysis_id: analysis_id
  } do
    previous =
      Application.get_env(
        :analysis,
        Analysis.AnalysisStore,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            Analysis.AnalysisStore
          )

        value ->
          Application.put_env(
            :analysis,
            Analysis.AnalysisStore,
            value
          )
      end
    end)

    Application.put_env(
      :analysis,
      Analysis.AnalysisStore,
      adapter: RecordingAnalysisStore,
      store: :configured_analysis_store
    )

    analysis = AnalysisModel.new(analysis_id, 42)

    assert {:ok, 42} =
             Analyses.insert(analysis)

    assert_received {
      :analysis_store_insert,
      :configured_analysis_store,
      ^analysis
    }
  end
end
