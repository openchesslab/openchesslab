defmodule Chess.PawnStructureShiftTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "shifts a white pawn while preserving the rest of the structure" do
    source =
      Position.new()
      |> Position.put_piece(
        square("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("c7"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    expected =
      Position.new()
      |> Position.put_piece(
        square("h3"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("c7"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             source,
             :white,
             square("h2"),
             square("h3")
           ) ==
             {
               :ok,
               expected
             }
  end

  test "shifts a black pawn" do
    source =
      Position.new()
      |> Position.put_piece(
        square("b2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("c7"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    expected =
      Position.new()
      |> Position.put_piece(
        square("b2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("c6"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             source,
             :black,
             square("c7"),
             square("c6")
           ) ==
             {
               :ok,
               expected
             }
  end

  test "rejects a source without the requested pawn" do
    structure =
      Position.new()
      |> Position.put_piece(
        square("h2"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             structure,
             :white,
             square("h2"),
             square("h3")
           ) ==
             {:error, :missing_pawn}
  end

  test "rejects a destination occupied by either color pawn" do
    white_target =
      Position.new()
      |> Position.put_piece(
        square("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("h3"),
        {:white, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             white_target,
             :white,
             square("h2"),
             square("h3")
           ) ==
             {:error, :target_has_pawn}

    black_target =
      Position.new()
      |> Position.put_piece(
        square("h2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("h3"),
        {:black, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             black_target,
             :white,
             square("h2"),
             square("h3")
           ) ==
             {:error, :target_has_pawn}
  end

  test "rejects an unchanged square" do
    structure =
      Position.new()
      |> Position.put_piece(
        square("h2"),
        {:white, :pawn}
      )
      |> PawnStructure.from_position()

    assert PawnStructure.shift_pawn(
             structure,
             :white,
             square("h2"),
             square("h2")
           ) ==
             {:error, :same_square}
  end

  test "rejects invalid color and square inputs" do
    structure =
      PawnStructure.from_position(Position.starting_position())

    assert PawnStructure.shift_pawn(
             structure,
             :red,
             square("h2"),
             square("h3")
           ) ==
             {:error, :invalid_color}

    assert PawnStructure.shift_pawn(
             structure,
             :white,
             -1,
             square("h3")
           ) ==
             {:error, :invalid_square}

    assert PawnStructure.shift_pawn(
             structure,
             :white,
             square("h2"),
             64
           ) ==
             {:error, :invalid_square}
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
