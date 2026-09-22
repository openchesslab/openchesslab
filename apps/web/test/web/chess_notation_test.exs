defmodule Web.ChessNotationTest do
  use ExUnit.Case, async: true

  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias Web.ChessNotation

  test "formats a knight move in English" do
    position = Position.starting_position()

    assert ChessNotation.format(
             position,
             Transition.move(move("g1", "f3")),
             "en"
           ) == {:ok, "Nf3"}
  end

  test "formats a knight move in Dutch" do
    position = Position.starting_position()

    assert ChessNotation.format(
             position,
             Transition.move(move("g1", "f3")),
             "nl"
           ) == {:ok, "Pf3"}
  end

  test "localizes a Dutch knight move" do
    position = Position.starting_position()

    assert ChessNotation.format(
             position,
             Transition.move(move("g1", "f3")),
             "nl"
           ) == {:ok, "Pf3"}
  end

  test "does not change pawn notation" do
    position = Position.starting_position()

    assert ChessNotation.format(
             position,
             Transition.move(move("e2", "e4")),
             "nl"
           ) == {:ok, "e4"}
  end

  test "does not change castling notation" do
    position =
      Position.new(castling_rights: MapSet.new([:white_kingside]))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert ChessNotation.format(
             position,
             Transition.move(move("e1", "g1")),
             "nl"
           ) == {:ok, "O-O"}
  end

  test "localizes promotion notation" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("e7"), {:white, :pawn})

    transition =
      Transition.move(
        Move.new(
          square("e7"),
          square("e8"),
          :queen
        )
      )

    assert ChessNotation.format(position, transition, "nl") ==
             {:ok, "e8=D+"}
  end

  test "edit transitions do not have chess notation" do
    assert ChessNotation.format(
             Position.starting_position(),
             Transition.edit(),
             "nl"
           ) == :not_applicable
  end

  defp move(from, to) do
    Move.new(square(from), square(to))
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
