defmodule Analysis.PositionQueryFileReflectedPawnStructureTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds a file-reflected pawn structure query from a position" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f6"),
        {:black, :pawn}
      )

    expected =
      position
      |> PawnStructure.from_position()
      |> PawnStructure.file_reflected()

    assert PositionQuery.file_reflected_pawn_structure(position) ==
             {
               :property,
               :pawn_structure,
               expected
             }
  end

  test "builds a file-reflected query from an explicit pawn structure" do
    structure =
      %PawnStructure{
        white: 0x0000000002000000,
        black: 0x0000200000000000
      }

    assert PositionQuery.file_reflected_pawn_structure(structure) ==
             {
               :property,
               :pawn_structure,
               PawnStructure.file_reflected(structure)
             }
  end
end
