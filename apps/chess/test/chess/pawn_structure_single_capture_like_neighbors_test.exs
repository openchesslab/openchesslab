defmodule Chess.PawnStructureSingleCaptureLikeNeighborsTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "includes forward and reverse capture-like displacements for both colors" do
    source =
      position([
        {"e4", {:white, :pawn}},
        {"c5", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    expected =
      [
        position([
          {"d5", {:white, :pawn}},
          {"c5", {:black, :pawn}}
        ]),
        position([
          {"f5", {:white, :pawn}},
          {"c5", {:black, :pawn}}
        ]),
        position([
          {"d3", {:white, :pawn}},
          {"c5", {:black, :pawn}}
        ]),
        position([
          {"f3", {:white, :pawn}},
          {"c5", {:black, :pawn}}
        ]),
        position([
          {"e4", {:white, :pawn}},
          {"b4", {:black, :pawn}}
        ]),
        position([
          {"e4", {:white, :pawn}},
          {"d4", {:black, :pawn}}
        ]),
        position([
          {"e4", {:white, :pawn}},
          {"b6", {:black, :pawn}}
        ]),
        position([
          {"e4", {:white, :pawn}},
          {"d6", {:black, :pawn}}
        ])
      ]
      |> Enum.map(&PawnStructure.from_position/1)

    assert PawnStructure.single_capture_like_neighbors(source) ==
             expected
  end

  test "can create and reverse a doubled-pawn structure" do
    source =
      position([
        {"d4", {:white, :pawn}},
        {"e4", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    doubled =
      position([
        {"d4", {:white, :pawn}},
        {"d5", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    assert doubled in PawnStructure.single_capture_like_neighbors(source)

    assert source in PawnStructure.single_capture_like_neighbors(doubled)
  end

  test "does not wrap across board edges" do
    source =
      position([
        {"a4", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    expected =
      [
        position([
          {"b5", {:white, :pawn}}
        ]),
        position([
          {"b3", {:white, :pawn}}
        ])
      ]
      |> Enum.map(&PawnStructure.from_position/1)

    assert PawnStructure.single_capture_like_neighbors(source) ==
             expected
  end

  test "omits destinations already occupied by a pawn" do
    source =
      position([
        {"e4", {:white, :pawn}},
        {"d5", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    collapsed =
      position([
        {"d5", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    refute collapsed in PawnStructure.single_capture_like_neighbors(source)
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
