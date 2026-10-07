defmodule Chess.PawnStructureSinglePawnRemovalsTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "removes exactly one pawn at a time" do
    source =
      position([
        {"h2", {:white, :pawn}},
        {"d4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    expected =
      [
        position([
          {"d4", {:white, :pawn}},
          {"c7", {:black, :pawn}}
        ]),
        position([
          {"h2", {:white, :pawn}},
          {"c7", {:black, :pawn}}
        ]),
        position([
          {"h2", {:white, :pawn}},
          {"d4", {:white, :pawn}}
        ])
      ]
      |> Enum.map(&PawnStructure.from_position/1)

    assert PawnStructure.single_pawn_removals(source) ==
             expected
  end

  test "returns no variants for an empty pawn structure" do
    source =
      Position.new()
      |> PawnStructure.from_position()

    assert PawnStructure.single_pawn_removals(source) ==
             []
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
