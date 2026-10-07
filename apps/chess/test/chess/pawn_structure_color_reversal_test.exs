defmodule Chess.PawnStructureColorReversalTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "swaps pawn colors and reflects ranks while preserving files" do
    structure =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    expected =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("c3"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d5"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.color_reversed(structure) ==
             expected
  end

  test "color reversal is its own inverse" do
    structure =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e5"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("h7"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert structure
           |> PawnStructure.color_reversed()
           |> PawnStructure.color_reversed() ==
             structure
  end

  test "starting pawn structure is invariant under color reversal" do
    structure =
      Position.starting_position()
      |> PawnStructure.from_position()

    assert PawnStructure.color_reversed(structure) ==
             structure
  end
end
