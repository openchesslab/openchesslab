defmodule Chess.PawnStructureSingleRankNeighborsTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "includes both forward and reverse one-rank neighbors" do
    source =
      position([
        {"h3", {:white, :pawn}},
        {"c6", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    expected =
      [
        position([
          {"h4", {:white, :pawn}},
          {"c6", {:black, :pawn}}
        ]),
        position([
          {"h2", {:white, :pawn}},
          {"c6", {:black, :pawn}}
        ]),
        position([
          {"h3", {:white, :pawn}},
          {"c5", {:black, :pawn}}
        ]),
        position([
          {"h3", {:white, :pawn}},
          {"c7", {:black, :pawn}}
        ])
      ]
      |> Enum.map(&PawnStructure.from_position/1)

    assert PawnStructure.single_rank_neighbors(source) ==
             expected
  end

  test "the neighborhood relation is symmetric" do
    lower =
      position([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    higher =
      position([
        {"h3", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    assert higher in PawnStructure.single_rank_neighbors(lower)

    assert lower in PawnStructure.single_rank_neighbors(higher)
  end

  test "omits occupied and off-board destinations" do
    source =
      position([
        {"a1", {:white, :pawn}},
        {"a2", {:black, :pawn}},
        {"a3", {:white, :pawn}},
        {"a4", {:black, :pawn}},
        {"a5", {:white, :pawn}},
        {"a6", {:black, :pawn}},
        {"a7", {:white, :pawn}},
        {"a8", {:black, :pawn}}
      ])
      |> PawnStructure.from_position()

    assert PawnStructure.single_rank_neighbors(source) ==
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
