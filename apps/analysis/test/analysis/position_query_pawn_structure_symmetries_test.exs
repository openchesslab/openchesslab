defmodule Analysis.PositionQueryPawnStructureSymmetriesTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds an OR query for every distinct symmetry" do
    structure =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f6"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    expected_queries =
      structure
      |> PawnStructure.symmetries()
      |> Enum.map(&PositionQuery.pawn_structure/1)

    assert PositionQuery.pawn_structure_symmetries(structure) ==
             {
               :or,
               expected_queries
             }
  end

  test "does not produce duplicate predicates for a symmetric structure" do
    structure =
      Position.starting_position()
      |> PawnStructure.from_position()

    query =
      PositionQuery.pawn_structure(structure)

    assert PositionQuery.pawn_structure_symmetries(structure) ==
             {
               :or,
               [
                 query
               ]
             }
  end
end
