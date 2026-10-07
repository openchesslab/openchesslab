defmodule Chess.PawnStructureFileReflectionTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "reflects files while preserving ranks and colors" do
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

    expected =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("g4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.file_reflected(structure) ==
             expected
  end

  test "file reflection is its own inverse" do
    structure =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f5"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("h7"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert structure
           |> PawnStructure.file_reflected()
           |> PawnStructure.file_reflected() ==
             structure
  end

  test "symmetric structure is invariant under file reflection" do
    structure =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f6"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.file_reflected(structure) ==
             structure
  end
end
