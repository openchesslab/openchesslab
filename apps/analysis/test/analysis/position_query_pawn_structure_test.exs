defmodule Analysis.PositionQueryPawnStructureTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position

  test "builds pawn structure query from a position" do
    position =
      Position.starting_position()

    assert PositionQuery.pawn_structure(position) ==
             {
               :property,
               :pawn_structure,
               PawnStructure.from_position(position)
             }
  end

  test "builds pawn structure query from an explicit structure" do
    structure =
      %PawnStructure{
        white: 123,
        black: 456
      }

    assert PositionQuery.pawn_structure(structure) ==
             {
               :property,
               :pawn_structure,
               structure
             }
  end
end
