defmodule Chess.PawnStructureSymmetriesTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "returns all four distinct symmetry variants" do
    structure =
      structure(
        "b4",
        "f6"
      )

    assert PawnStructure.symmetries(structure) ==
             [
               structure(
                 "b4",
                 "f6"
               ),
               structure(
                 "f3",
                 "b5"
               ),
               structure(
                 "g4",
                 "c6"
               ),
               structure(
                 "c3",
                 "g5"
               )
             ]
  end

  test "removes duplicate symmetry variants" do
    structure =
      Position.starting_position()
      |> PawnStructure.from_position()

    assert PawnStructure.symmetries(structure) ==
             [
               structure
             ]
  end

  test "color reversal and file reflection commute" do
    structure =
      structure(
        "b4",
        "f6"
      )

    left =
      structure
      |> PawnStructure.color_reversed()
      |> PawnStructure.file_reflected()

    right =
      structure
      |> PawnStructure.file_reflected()
      |> PawnStructure.color_reversed()

    assert left ==
             right
  end

  defp structure(white_square, black_square) do
    Position.new()
    |> Position.put_piece(
      Square.from_algebraic(white_square),
      {:white, :pawn}
    )
    |> Position.put_piece(
      Square.from_algebraic(black_square),
      {:black, :pawn}
    )
    |> PawnStructure.from_position()
  end
end
