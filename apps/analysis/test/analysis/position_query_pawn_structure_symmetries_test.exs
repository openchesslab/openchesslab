defmodule Analysis.PositionQueryPawnStructureSymmetriesTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds a bounded pawn structure set containing every distinct symmetry" do
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

    structure =
      PawnStructure.from_position(position)

    symmetries =
      PawnStructure.symmetries(structure)

    assert length(symmetries) ==
             4

    assert PositionQuery.pawn_structure_symmetries(structure) ==
             {
               :pawn_structures,
               symmetries
             }

    assert PositionQuery.pawn_structure_symmetries(position) ==
             {
               :pawn_structures,
               symmetries
             }
  end

  test "keeps a collapsed symmetry class as one bounded structure set" do
    structure =
      Position.starting_position()
      |> PawnStructure.from_position()

    assert PawnStructure.symmetries(structure) ==
             [
               structure
             ]

    assert PositionQuery.pawn_structure_symmetries(structure) ==
             {
               :pawn_structures,
               [
                 structure
               ]
             }
  end
end
