defmodule Chess.Notation.SANTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.SAN
  alias Chess.Position
  alias Chess.Square

  test "formats a pawn move" do
    position = Position.starting_position()

    assert SAN.format(position, move("e2", "e4")) ==
             {:ok, "e4"}
  end

  test "formats a piece move" do
    position = Position.starting_position()

    assert SAN.format(position, move("g1", "f3")) ==
             {:ok, "Nf3"}
  end

  test "formats a piece capture" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("f3"), {:white, :knight})
      |> Position.put_piece(square("e5"), {:black, :pawn})

    assert SAN.format(position, move("f3", "e5")) ==
             {:ok, "Nxe5"}
  end

  test "formats a pawn capture with its source file" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("e4"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    assert SAN.format(position, move("e4", "d5")) ==
             {:ok, "exd5"}
  end

  test "rejects an illegal move" do
    position = Position.starting_position()

    assert SAN.format(position, move("e2", "e5")) ==
             {:error, :illegal_move}
  end

  defp move(from, to) do
    Move.new(square(from), square(to))
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
