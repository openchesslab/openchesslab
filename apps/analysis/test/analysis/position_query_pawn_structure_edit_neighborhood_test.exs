defmodule Analysis.PositionQueryPawnStructureEditNeighborhoodTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Chess.Position
  alias Chess.Square

  test "materializes the bounded edit neighborhood once in the query" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("h7"),
        {:black, :pawn}
      )

    structure =
      PawnStructure.from_position(position)

    expected =
      EditDistance.neighborhood(
        structure,
        2
      )

    assert PositionQuery.pawn_structure_edit_neighborhood(
             structure,
             2
           ) ==
             {
               :pawn_structure_edit_neighborhood,
               expected
             }

    assert PositionQuery.pawn_structure_edit_neighborhood(
             position,
             2
           ) ==
             {
               :pawn_structure_edit_neighborhood,
               expected
             }
  end

  test "supports distances zero and one" do
    structure =
      %PawnStructure{
        white:
          Bitwise.bsl(
            1,
            Square.from_algebraic("d4")
          ),
        black: 0
      }

    assert {
             :pawn_structure_edit_neighborhood,
             [
               ^structure
             ]
           } =
             PositionQuery.pawn_structure_edit_neighborhood(
               structure,
               0
             )

    assert {
             :pawn_structure_edit_neighborhood,
             structures
           } =
             PositionQuery.pawn_structure_edit_neighborhood(
               structure,
               1
             )

    assert structures ==
             EditDistance.neighborhood(
               structure,
               1
             )
  end
end
