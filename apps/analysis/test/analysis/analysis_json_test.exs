defmodule Analysis.AnalysisJSONTest do
  use ExUnit.Case, async: false

  alias Analysis.AnalysisJSON
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  # The mainline's SANs, walking down the tree's first child.
  defp mainline_sans(node) do
    case node.children do
      [child | _] -> [child.san | mainline_sans(child)]
      [] -> []
    end
  end

  # Build a mainline analysis from algebraic move pairs, appending the
  # resulting positions to the store.
  defp analysis_from_moves(moves) do
    start = Position.starting_position()
    start_id = Analysis.PositionStore.append(start)

    {nodes, _position} =
      Enum.reduce(moves, {[], start}, fn {from, to}, {nodes, position} ->
        move = Move.new(Square.from_algebraic(from), Square.from_algebraic(to))
        {:ok, next} = Position.apply_move(position, move)
        id = Analysis.PositionStore.append(next)

        node = %Analysis.Node{
          position_id: id,
          transition: Analysis.Transition.move(move)
        }

        {nodes ++ [node], next}
      end)

    children =
      Enum.reduce(Enum.reverse(nodes), [], fn node, acc ->
        [%{node | children: acc}]
      end)

    %Analysis.Analysis{
      id: "san-analysis",
      root: %Analysis.Node{position_id: start_id, children: children},
      start: Analysis.GameStart.standard()
    }
  end

  describe "expand/2" do
    test "an empty analysis expands to a tree with one root node" do
      analysis = Analysis.Analysis.new("a1", Square.from_algebraic("e2"))
      json = AnalysisJSON.expand(analysis, revision: 1)

      assert json.id == "a1"
      assert json.revision == 1
      assert is_map(json.start)
      assert json.source_game_record_id == nil
      assert json.metadata == %{}

      assert json.root.position_id == Square.from_algebraic("e2")
      assert json.root.transition == nil
      assert json.root.comment == nil
      assert json.root.san == nil
      assert json.root.children == []
    end

    test "embeds a position per node by looking it up in PositionStore" do
      starting_position = Position.starting_position()

      starting_position_id = Analysis.PositionStore.append(starting_position)
      analysis = Analysis.Analysis.new("a2", starting_position_id)
      json = AnalysisJSON.expand(analysis, revision: 7)

      assert json.revision == 7
      assert json.root.position == starting_position
    end

    test "walks the tree recursively so children also get positions" do
      start = Position.starting_position()
      start_id = Analysis.PositionStore.append(start)

      after_e2 =
        start
        |> Position.apply_move(Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4")))
        |> elem(1)

      after_e2_id = Analysis.PositionStore.append(after_e2)

      e2e4 =
        Analysis.Transition.move(Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4")))

      analysis = %Analysis.Analysis{
        id: "a3",
        root: %Analysis.Node{
          position_id: start_id,
          children: [%Analysis.Node{position_id: after_e2_id, transition: e2e4}]
        },
        start: Analysis.GameStart.standard(),
        source_game_record_id: nil,
        metadata: %{}
      }

      json = AnalysisJSON.expand(analysis, revision: 3)

      assert json.root.position == start

      [child] = json.root.children
      assert child.position == after_e2

      assert child.transition == %{
               type: "move",
               from: Square.from_algebraic("e2"),
               to: Square.from_algebraic("e4"),
               promotion: nil
             }
    end

    test "shares PositionStore lookups across transposition nodes (one fetch per position_id)" do
      start = Position.starting_position()
      start_id = Analysis.PositionStore.append(start)

      analysis = %Analysis.Analysis{
        id: "a4",
        root: %Analysis.Node{
          position_id: start_id,
          children: [
            %Analysis.Node{position_id: start_id, transition: Analysis.Transition.edit()},
            %Analysis.Node{position_id: start_id, transition: Analysis.Transition.edit()}
          ]
        },
        start: Analysis.GameStart.standard(),
        source_game_record_id: nil,
        metadata: %{}
      }

      json = AnalysisJSON.expand(analysis, revision: 1)

      assert json.root.position == start
      assert Enum.map(json.root.children, & &1.position) == [start, start]
    end

    test "a missing position surfaces as nil rather than raising" do
      analysis = Analysis.Analysis.new("a5", 9999)
      json = AnalysisJSON.expand(analysis, revision: 1)

      assert json.root.position_id == 9999
      assert json.root.position == nil
    end

    test "an :edit transition serializes to {type: 'edit'}" do
      start = Position.starting_position()
      start_id = Analysis.PositionStore.append(start)

      analysis = %Analysis.Analysis{
        id: "a6",
        root: %Analysis.Node{
          position_id: start_id,
          children: [%Analysis.Node{position_id: start_id, transition: :edit}]
        },
        start: Analysis.GameStart.standard(),
        source_game_record_id: nil,
        metadata: %{}
      }

      json = AnalysisJSON.expand(analysis, revision: 1)

      [child] = json.root.children
      assert child.transition == %{type: "edit"}
    end

    test "labels transitions with canonical SAN, including check and mate" do
      # Scholar's mate: 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
      analysis =
        analysis_from_moves([
          {"e2", "e4"},
          {"e7", "e5"},
          {"d1", "h5"},
          {"b8", "c6"},
          {"f1", "c4"},
          {"g8", "f6"},
          {"h5", "f7"}
        ])

      json = AnalysisJSON.expand(analysis, revision: 1)

      assert mainline_sans(json.root) == ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"]
    end

    test "labels castling as O-O" do
      analysis =
        analysis_from_moves([
          {"e2", "e4"},
          {"e7", "e5"},
          {"g1", "f3"},
          {"b8", "c6"},
          {"f1", "c4"},
          {"f8", "c5"},
          {"e1", "g1"}
        ])

      json = AnalysisJSON.expand(analysis, revision: 1)

      assert List.last(mainline_sans(json.root)) == "O-O"
    end
  end
end
