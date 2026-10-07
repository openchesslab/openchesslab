defmodule Analysis.PositionQueryPawnStructureSinglePushNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds a direction-independent bounded single-push neighborhood" do
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
        | PawnStructure.single_rank_neighbors(structure)
      ]

    assert length(expected) ==
             5

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
