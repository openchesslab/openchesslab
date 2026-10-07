defmodule Analysis.PositionQueryPawnStructureMissingPawnNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds the exact structure and every one-missing-pawn variant" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d4"),
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
        | PawnStructure.single_pawn_removals(structure)
      ]

    assert length(expected) ==
             4

    assert PositionQuery.pawn_structure_missing_pawn_neighborhood(structure) ==
             {
               :pawn_structures,
               expected
             }

    assert PositionQuery.pawn_structure_missing_pawn_neighborhood(position) ==
             {
               :pawn_structures,
               expected
             }
  end
end
