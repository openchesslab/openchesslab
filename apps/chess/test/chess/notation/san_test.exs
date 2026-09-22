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

  test "formats kingside castling" do
    position =
      Position.new(castling_rights: MapSet.new([:white_kingside]))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert SAN.format(position, move("e1", "g1")) ==
             {:ok, "O-O"}
  end

  test "formats queenside castling" do
    position =
      Position.new(castling_rights: MapSet.new([:white_queenside]))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert SAN.format(position, move("e1", "c1")) ==
             {:ok, "O-O-O"}
  end

  test "formats an en passant capture" do
    position =
      Position.new(
        side_to_move: :white,
        en_passant: square("d6")
      )
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("e5"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    assert SAN.format(position, move("e5", "d6")) ==
             {:ok, "exd6"}
  end

  test "formats a promotion" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("e7"), {:white, :pawn})

    assert SAN.format(
             position,
             Move.new(
               square("e7"),
               square("e8"),
               :queen
             )
           ) == {:ok, "e8=Q+"}
  end

  test "formats a promotion capture" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h8"), {:black, :king})
      |> Position.put_piece(square("e7"), {:white, :pawn})
      |> Position.put_piece(square("d8"), {:black, :rook})

    assert SAN.format(
             position,
             Move.new(
               square("e7"),
               square("d8"),
               :knight
             )
           ) == {:ok, "exd8=N"}
  end

  test "disambiguates pieces by file" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("b1"), {:white, :knight})
      |> Position.put_piece(square("f1"), {:white, :knight})

    assert SAN.format(position, move("b1", "d2")) ==
             {:ok, "Nbd2"}

    assert SAN.format(position, move("f1", "d2")) ==
             {:ok, "Nfd2"}
  end

  test "disambiguates pieces by rank when they share a file" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("a1"), {:white, :rook})
      |> Position.put_piece(square("a3"), {:white, :rook})

    assert SAN.format(position, move("a1", "a2")) ==
             {:ok, "R1a2"}

    assert SAN.format(position, move("a3", "a2")) ==
             {:ok, "R3a2"}
  end

  test "disambiguates pieces by file and rank when both are required" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("b1"), {:white, :knight})
      |> Position.put_piece(square("b3"), {:white, :knight})
      |> Position.put_piece(square("f1"), {:white, :knight})

    assert SAN.format(position, move("b1", "d2")) ==
             {:ok, "Nb1d2"}
  end

  test "does not disambiguate against a piece that cannot legally move" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e2"), {:white, :knight})
      |> Position.put_piece(square("c2"), {:white, :knight})
      |> Position.put_piece(square("e8"), {:black, :rook})
      |> Position.put_piece(square("a8"), {:black, :king})

    assert SAN.format(position, move("c2", "d4")) ==
             {:ok, "Nd4"}
  end

  test "formats check" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})

    assert SAN.format(position, move("h1", "h8")) ==
             {:ok, "Rh8+"}
  end

  test "formats checkmate" do
    position =
      Position.new()
      |> Position.put_piece(square("f6"), {:white, :king})
      |> Position.put_piece(square("g6"), {:white, :queen})
      |> Position.put_piece(square("h8"), {:black, :king})

    assert SAN.format(position, move("g6", "g7")) ==
             {:ok, "Qg7#"}
  end

  defp move(from, to) do
    Move.new(square(from), square(to))
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
