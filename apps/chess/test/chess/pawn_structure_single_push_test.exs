defmodule Chess.PawnStructureSinglePushTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "builds one distinct variant for every available single forward pawn shift" do
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
          {"h3", {:white, :pawn}},
          {"d4", {:white, :pawn}},
          {"c7", {:black, :pawn}}
        ]),
        position([
          {"h2", {:white, :pawn}},
          {"d5", {:white, :pawn}},
          {"c7", {:black, :pawn}}
        ]),
        position([
          {"h2", {:white, :pawn}},
          {"d4", {:white, :pawn}},
          {"c6", {:black, :pawn}}
        ])
      ]
      |> Enum.map(&PawnStructure.from_position/1)

    assert PawnStructure.single_pushes(source) ==
             expected
  end

  test "omits shifts whose target contains another pawn" do
    source =
      position([
        {"a2", {:white, :pawn}},
        {"a3", {:black, :pawn}},
        {"h7", {:black, :pawn}},
        {"h6", {:white, :pawn}}
      ])
      |> PawnStructure.from_position()

    assert PawnStructure.single_pushes(source) ==
             []
  end

  test "omits shifts that leave the board" do
    source =
      position([
        {"a8", {:white, :pawn}},
        {"h1", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    assert PawnStructure.single_pushes(source) ==
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
