defmodule Analysis.PositionQueryPawnStructureSinglePushNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds a bounded set containing the exact structure and every single push" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c7"),
        {:black, :pawn}
      )

    structure =
      PawnStructure.from_position(position)

    expected =
      [
        structure
        | PawnStructure.single_pushes(structure)
      ]

    assert PositionQuery.pawn_structure_single_push_neighborhood(structure) ==
             {
               :pawn_structures,
               expected
             }

    assert PositionQuery.pawn_structure_single_push_neighborhood(position) ==
             {
               :pawn_structures,
               expected
             }
  end
end
