defmodule Chess.PawnStructureEditDistanceTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance
  alias Chess.Position
  alias Chess.Square

  test "exact structures have distance zero" do
    structure =
      pawn_structure([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    assert EditDistance.bounded(
             structure,
             structure,
             0
           ) ==
             {:ok, 0}

    assert EditDistance.within?(
             structure,
             structure,
             0
           )
  end

  test "one-rank displacements have distance one in either direction" do
    h2 =
      pawn_structure([
        {"h2", {:white, :pawn}}
      ])

    h3 =
      pawn_structure([
        {"h3", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             h2,
             h3,
             1
           ) ==
             {:ok, 1}

    assert EditDistance.bounded(
             h3,
             h2,
             1
           ) ==
             {:ok, 1}
  end

  test "capture-like displacements have distance one in either direction" do
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

    assert EditDistance.bounded(
             source,
             doubled,
             1
           ) ==
             {:ok, 1}

    assert EditDistance.bounded(
             doubled,
             source,
             1
           ) ==
             {:ok, 1}
  end

  test "pawn removal has distance one only in the removal direction" do
    full =
      pawn_structure([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    reduced =
      pawn_structure([
        {"c7", {:black, :pawn}}
      ])

    assert EditDistance.bounded(
             full,
             reduced,
             1
           ) ==
             {:ok, 1}

    assert EditDistance.bounded(
             reduced,
             full,
             1
           ) ==
             :beyond_limit

    refute EditDistance.within?(
             reduced,
             full,
             2
           )
  end

  test "a two-rank displacement has distance two" do
    h2 =
      pawn_structure([
        {"h2", {:white, :pawn}}
      ])

    h4 =
      pawn_structure([
        {"h4", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             h2,
             h4,
             1
           ) ==
             :beyond_limit

    assert EditDistance.bounded(
             h2,
             h4,
             2
           ) ==
             {:ok, 2}

    assert EditDistance.bounded(
             h4,
             h2,
             2
           ) ==
             {:ok, 2}
  end

  test "two independent single-rank displacements have distance two" do
    source =
      pawn_structure([
        {"a2", {:white, :pawn}},
        {"e2", {:white, :pawn}}
      ])

    target =
      pawn_structure([
        {"a3", {:white, :pawn}},
        {"e3", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             source,
             target,
             1
           ) ==
             :beyond_limit

    assert EditDistance.bounded(
             source,
             target,
             2
           ) ==
             {:ok, 2}
  end

  test "one displacement plus one pawn removal has distance two" do
    source =
      pawn_structure([
        {"a2", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    target =
      pawn_structure([
        {"a3", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             source,
             target,
             1
           ) ==
             :beyond_limit

    assert EditDistance.bounded(
             source,
             target,
             2
           ) ==
             {:ok, 2}
  end

  test "three single-rank displacements are beyond distance two" do
    source =
      pawn_structure([
        {"a2", {:white, :pawn}},
        {"c2", {:white, :pawn}},
        {"e2", {:white, :pawn}}
      ])

    target =
      pawn_structure([
        {"a3", {:white, :pawn}},
        {"c3", {:white, :pawn}},
        {"e3", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             source,
             target,
             2
           ) ==
             :beyond_limit
  end

  test "a distant relocation is not collapsed into removal plus addition" do
    h2 =
      pawn_structure([
        {"h2", {:white, :pawn}}
      ])

    h8 =
      pawn_structure([
        {"h8", {:white, :pawn}}
      ])

    assert EditDistance.bounded(
             h2,
             h8,
             2
           ) ==
             :beyond_limit
  end

  test "invalid occupied relocation is not considered reachable" do
    source =
      %PawnStructure{
        white: square_bit("h2"),
        black: square_bit("h3")
      }

    target =
      %PawnStructure{
        white: square_bit("h3"),
        black: square_bit("h3")
      }

    assert EditDistance.bounded(
             source,
             target,
             1
           ) ==
             :beyond_limit
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

  defp square_bit(square) do
    Bitwise.bsl(
      1,
      Square.from_algebraic(square)
    )
  end
end
