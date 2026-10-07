defmodule Analysis.PositionQueryPawnStructuresTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Analysis.PositionQueryNormalizer
  alias Chess.PawnStructure

  test "builds a bounded pawn structure set query" do
    first =
      %PawnStructure{
        white: 1,
        black: 2
      }

    second =
      %PawnStructure{
        white: 4,
        black: 8
      }

    assert PositionQuery.pawn_structures([
             first,
             second
           ]) ==
             {
               :pawn_structures,
               [
                 first,
                 second
               ]
             }
  end

  test "normalization removes duplicate structures" do
    structure =
      %PawnStructure{
        white: 1,
        black: 2
      }

    query =
      PositionQuery.pawn_structures([
        structure,
        structure
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             {
               :pawn_structures,
               [
                 structure
               ]
             }
  end

  test "an empty structure set normalizes to match none" do
    assert []
           |> PositionQuery.pawn_structures()
           |> PositionQueryNormalizer.normalize() ==
             false
  end
end
