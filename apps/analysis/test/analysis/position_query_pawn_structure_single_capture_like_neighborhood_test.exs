defmodule Analysis.PositionQueryPawnStructureSingleCaptureLikeNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds the exact structure and every capture-like neighbor" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("e4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c5"),
        {:black, :pawn}
      )

    structure =
      PawnStructure.from_position(position)

    expected =
      [
        structure
        | PawnStructure.single_capture_like_neighbors(structure)
      ]

    assert length(expected) ==
             9

    assert PositionQuery.pawn_structure_single_capture_like_neighborhood(structure) ==
             {
               :pawn_structures,
               expected
             }

    assert PositionQuery.pawn_structure_single_capture_like_neighborhood(position) ==
             {
               :pawn_structures,
               expected
             }
  end
end
