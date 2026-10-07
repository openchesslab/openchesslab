defmodule Chess.PawnStructureDifferenceTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Chess.PawnStructure
  alias Chess.PawnStructure.Difference
  alias Chess.Position
  alias Chess.Square

  test "exact structures have an empty difference" do
    structure =
      pawn_structure([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    difference =
      PawnStructure.difference(
        structure,
        structure
      )

    assert difference ==
             %Difference{
               white_removed: 0,
               white_added: 0,
               black_removed: 0,
               black_added: 0
             }

    assert Difference.classify(difference) ==
             :exact
  end

  test "distinguishes a removed pawn from an added pawn" do
    full =
      pawn_structure([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    reduced =
      pawn_structure([
        {"c7", {:black, :pawn}}
      ])

    h2 =
      Square.from_algebraic("h2")

    removed =
      PawnStructure.difference(
        full,
        reduced
      )

    assert removed.white_removed ==
             bsl(
               1,
               h2
             )

    assert removed.white_added ==
             0

    assert Difference.classify(removed) ==
             {
               :single_pawn_removal,
               :white,
               h2
             }

    added =
      PawnStructure.difference(
        reduced,
        full
      )

    assert Difference.classify(added) ==
             {
               :single_pawn_addition,
               :white,
               h2
             }
  end

  test "classifies a one-rank displacement as one elementary edit" do
    lower =
      pawn_structure([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    higher =
      pawn_structure([
        {"h3", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    h2 =
      Square.from_algebraic("h2")

    h3 =
      Square.from_algebraic("h3")

    assert lower
           |> PawnStructure.difference(higher)
           |> Difference.classify() ==
             {
               :single_rank_displacement,
               :white,
               h2,
               h3
             }

    assert higher
           |> PawnStructure.difference(lower)
           |> Difference.classify() ==
             {
               :single_rank_displacement,
               :white,
               h3,
               h2
             }
  end

  test "classifies a capture-like displacement as one elementary edit" do
    source =
      pawn_structure([
        {"d4", {:white, :pawn}},
        {"e4", {:white, :pawn}}
      ])

    doubled =
      pawn_structure([
        {"d4", {:white, :pawn}},
        {"d5", {:white, :pawn}}
      ])

    e4 =
      Square.from_algebraic("e4")

    d5 =
      Square.from_algebraic("d5")

    assert source
           |> PawnStructure.difference(doubled)
           |> Difference.classify() ==
             {
               :single_capture_like_displacement,
               :white,
               e4,
               d5
             }

    assert doubled
           |> PawnStructure.difference(source)
           |> Difference.classify() ==
             {
               :single_capture_like_displacement,
               :white,
               d5,
               e4
             }
  end

  test "a two-rank displacement is not one elementary edit" do
    h2 =
      pawn_structure([
        {"h2", {:white, :pawn}}
      ])

    h4 =
      pawn_structure([
        {"h4", {:white, :pawn}}
      ])

    assert h2
           |> PawnStructure.difference(h4)
           |> Difference.classify() ==
             :not_single_edit
  end

  test "two independent one-rank displacements are not one elementary edit" do
    source =
      pawn_structure([
        {"a2", {:white, :pawn}},
        {"e2", {:white, :pawn}}
      ])

    target =
      pawn_structure([
        {"a3", {:white, :pawn}},
        {"e4", {:white, :pawn}}
      ])

    assert source
           |> PawnStructure.difference(target)
           |> Difference.classify() ==
             :not_single_edit
  end

  test "changes to both colors are not one elementary edit" do
    source =
      pawn_structure([
        {"a2", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    target =
      pawn_structure([
        {"a3", {:white, :pawn}},
        {"h6", {:black, :pawn}}
      ])

    assert source
           |> PawnStructure.difference(target)
           |> Difference.classify() ==
             :not_single_edit
  end

  defp pawn_structure(pieces) do
    pieces
    |> position()
    |> PawnStructure.from_position()
  end

  defp position(pieces) do
    Enum.reduce(
      pieces,
      Position.new(),
      fn
        {
          square,
          piece
        },
        position ->
          Position.put_piece(
            position,
            Square.from_algebraic(square),
            piece
          )
      end
    )
  end
end
