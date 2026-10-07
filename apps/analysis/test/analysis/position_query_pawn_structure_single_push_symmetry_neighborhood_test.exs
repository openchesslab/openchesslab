defmodule Analysis.PositionQueryPawnStructureSinglePushSymmetryNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds the distinct symmetries of the exact structure and every direction-independent neighbor" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f7"),
        {:black, :pawn}
      )

    structure =
      PawnStructure.from_position(position)

    expected =
      [
        structure
        | PawnStructure.single_rank_neighbors(structure)
      ]
      |> Enum.flat_map(&PawnStructure.symmetries/1)
      |> Enum.uniq()

    assert length(expected) ==
             20

    assert PositionQuery.pawn_structure_single_push_symmetry_neighborhood(structure) ==
             {
               :pawn_structures,
               expected
             }

    assert PositionQuery.pawn_structure_single_push_symmetry_neighborhood(position) ==
             {
               :pawn_structures,
               expected
             }
  end
end
