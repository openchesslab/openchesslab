defmodule Analysis.PositionQueryColorReversedPawnStructureTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds a color-reversed pawn structure query from a position" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )

    expected =
      position
      |> PawnStructure.from_position()
      |> PawnStructure.color_reversed()

    assert PositionQuery.color_reversed_pawn_structure(position) ==
             {
               :property,
               :pawn_structure,
               expected
             }
  end

  test "builds a color-reversed query from an explicit pawn structure" do
    structure =
      %PawnStructure{
        white: 0x0000000008000000,
        black: 0x0000040000000000
      }

    assert PositionQuery.color_reversed_pawn_structure(structure) ==
             {
               :property,
               :pawn_structure,
               PawnStructure.color_reversed(structure)
             }
  end
end
