defmodule Chess.PawnStructureTest do
  use ExUnit.Case, async: true

  alias Chess.Bitboard
  alias Chess.PawnStructure
  alias Chess.Position
  alias Chess.Square

  test "extracts starting pawn occupancy" do
    assert PawnStructure.from_position(Position.starting_position()) ==
             %PawnStructure{
               white: 0x000000000000FF00,
               black: 0x00FF000000000000
             }
  end

  test "ignores non-pawn pieces and position state" do
    first =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e5"),
        {:black, :pawn}
      )

    second =
      Position.new(side_to_move: :black)
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e5"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :queen}
      )
      |> Position.put_piece(
        Square.from_algebraic("h8"),
        {:black, :rook}
      )

    assert PawnStructure.from_position(first) ==
             PawnStructure.from_position(second)
  end

  test "works directly with a bitboard" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a2"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("h7"),
        {:black, :pawn}
      )

    board =
      Bitboard.from_position(position)

    assert PawnStructure.from_bitboard(board) ==
             PawnStructure.from_position(position)
  end
end
