defmodule Chess.Notation.SANTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.SAN
  alias Chess.Position
  alias Chess.Square

  test "resolves ordinary pawn advances without changing canonical SAN rules" do
    start = Position.starting_position()
    assert SAN.parse(start, "e4") == {:ok, move("e2", "e4")}
    assert SAN.parse(start, "e3") == {:ok, move("e2", "e3")}
    assert SAN.parse(start, "e5") == {:error, :invalid_san}
    assert SAN.parse(start, "e4+") == {:error, :invalid_san}
    assert SAN.parse(start, "e4#") == {:error, :invalid_san}

    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    assert SAN.parse(after_e4, "e5") == {:ok, move("e7", "e5")}

    blocked = Position.put_piece(start, square("e3"), {:white, :knight})
    assert SAN.parse(blocked, "e4") == {:error, :invalid_san}

    occupied = Position.put_piece(start, square("e4"), {:black, :knight})
    assert SAN.parse(occupied, "e4") == {:error, :invalid_san}
  end

  test "a pinned pawn cannot make an illegal quiet advance" do
    position =
      Position.new()
      |> Position.put_piece(square("b2"), {:white, :king})
      |> Position.put_piece(square("h8"), {:black, :king})
      |> Position.put_piece(square("c3"), {:white, :pawn})
      |> Position.put_piece(square("d4"), {:black, :bishop})

    assert SAN.parse(position, "c4") == {:error, :invalid_san}
  end

  test "accepts a canonical pawn check suffix and rejects other suffixes" do
    position =
      Position.new()
      |> Position.put_piece(square("a1"), {:white, :king})
      |> Position.put_piece(square("d5"), {:black, :king})
      |> Position.put_piece(square("e3"), {:white, :pawn})

    assert SAN.format(position, move("e3", "e4")) == {:ok, "e4+"}
    assert SAN.parse(position, "e4+") == {:ok, move("e3", "e4")}
    assert SAN.parse(position, "e4") == {:error, :invalid_san}
    assert SAN.parse(position, "e4#") == {:error, :invalid_san}
  end

  test "quiet pawn parsing agrees with legal move SAN over representative positions" do
    start = Position.starting_position()
    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    {:ok, after_e5} = Position.apply_move(after_e4, move("e7", "e5"))
    {:ok, after_nf3} = Position.apply_move(after_e5, move("g1", "f3"))

    pawn_check =
      Position.new()
      |> Position.put_piece(square("a1"), {:white, :king})
      |> Position.put_piece(square("d5"), {:black, :king})
      |> Position.put_piece(square("e3"), {:white, :pawn})

    for position <- [start, after_e4, after_e5, after_nf3, pawn_check] do
      canonical =
        position
        |> Position.legal_moves()
        |> Map.new(fn move ->
          {:ok, san} = SAN.format(position, move)
          {san, move}
        end)

      for square <- 0..63, suffix <- ["", "+", "#"] do
        notation = Square.to_algebraic(square) <> suffix

        expected =
          case Map.fetch(canonical, notation) do
            {:ok, move} -> {:ok, move}
            :error -> {:error, :invalid_san}
          end

        assert SAN.parse(position, notation) == expected,
               "Mismatch parsing #{notation} for #{inspect(position)}"
      end
    end
  end

  test "keeps non-pawn SAN parsing on the existing path" do
    position = Position.starting_position()
    assert SAN.parse(position, "Nf3") == {:ok, move("g1", "f3")}
    assert SAN.parse(position, "Nbd2") == {:error, :invalid_san}
  end

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
      [castling_rights: MapSet.new([:white_kingside])]
      |> Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert SAN.format(position, move("e1", "g1")) ==
             {:ok, "O-O"}
  end

  test "formats queenside castling" do
    position =
      [castling_rights: MapSet.new([:white_queenside])]
      |> Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert SAN.format(position, move("e1", "c1")) ==
             {:ok, "O-O-O"}
  end

  test "formats an en passant capture" do
    position =
      [side_to_move: :white, en_passant: square("d6")]
      |> Position.new()
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
