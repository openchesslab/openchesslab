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

  test "resolves pawn captures with canonical SAN and rejects noncanonical suffixes" do
    white =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("e4"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    expected = move("e4", "d5")
    assert SAN.format(white, expected) == {:ok, "exd5"}
    assert SAN.parse(white, "exd5") == {:ok, expected}
    assert SAN.parse(white, "exd5+") == {:error, :invalid_san}
    assert SAN.parse(white, "exd5#") == {:error, :invalid_san}
    assert SAN.parse(white, "fxd5") == {:error, :invalid_san}
    assert SAN.parse(white, "exh5") == {:error, :invalid_san}

    black =
      Position.new(side_to_move: :black)
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("d5"), {:black, :pawn})
      |> Position.put_piece(square("e4"), {:white, :pawn})

    assert SAN.format(black, move("d5", "e4")) == {:ok, "dxe4"}
    assert SAN.parse(black, "dxe4") == {:ok, move("d5", "e4")}
  end

  test "resolves en passant captures in both directions" do
    white =
      Position.new(side_to_move: :white, en_passant: square("d6"))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("e5"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    assert SAN.format(white, move("e5", "d6")) == {:ok, "exd6"}
    assert SAN.parse(white, "exd6") == {:ok, move("e5", "d6")}

    without_en_passant = %{white | en_passant: nil}
    assert SAN.parse(without_en_passant, "exd6") == {:error, :invalid_san}

    black =
      Position.new(side_to_move: :black, en_passant: square("e3"))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("d4"), {:black, :pawn})
      |> Position.put_piece(square("e4"), {:white, :pawn})

    assert SAN.format(black, move("d4", "e3")) == {:ok, "dxe3"}
    assert SAN.parse(black, "dxe3") == {:ok, move("d4", "e3")}
  end

  test "rejects a capture that exposes the moving side's king" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("e8"), {:black, :rook})
      |> Position.put_piece(square("e4"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    assert SAN.parse(position, "exd5") == {:error, :invalid_san}
  end

  test "promotion captures still use the reference SAN parser" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h8"), {:black, :king})
      |> Position.put_piece(square("e7"), {:white, :pawn})
      |> Position.put_piece(square("d8"), {:black, :rook})

    promotion = Move.new(square("e7"), square("d8"), :queen)
    assert {:ok, notation} = SAN.format(position, promotion)
    assert SAN.parse(position, notation) == {:ok, promotion}
  end

  test "pawn capture parsing agrees with canonical formatting on representative positions" do
    start = Position.starting_position()
    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    {:ok, after_e5} = Position.apply_move(after_e4, move("e7", "e5"))

    white =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("e4"), {:white, :pawn})
      |> Position.put_piece(square("d5"), {:black, :pawn})

    for position <- [start, after_e4, after_e5, white] do
      canonical =
        position
        |> Position.legal_moves()
        |> Map.new(fn move ->
          {:ok, notation} = SAN.format(position, move)
          {notation, move}
        end)

      for source_file <- ?a..?h, destination <- 0..63, suffix <- ["", "+", "#"] do
        notation = <<source_file, ?x>> <> Square.to_algebraic(destination) <> suffix

        expected =
          case Map.fetch(canonical, notation) do
            {:ok, move} -> {:ok, move}
            :error -> {:error, :invalid_san}
          end

        assert SAN.parse(position, notation) == expected,
               "Capture mismatch for #{notation}: #{inspect(position)}"
      end
    end
  end

  test "resolves ordinary piece SAN and rejects noncanonical checks and captures" do
    start = Position.starting_position()
    assert SAN.parse(start, "Nf3") == {:ok, move("g1", "f3")}
    assert SAN.parse(start, "Nf3+") == {:error, :invalid_san}
    assert SAN.parse(start, "Nf3#") == {:error, :invalid_san}
    assert SAN.parse(start, "Nxf3") == {:error, :invalid_san}
    assert SAN.parse(start, "Ng3") == {:error, :invalid_san}

    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    {:ok, after_e5} = Position.apply_move(after_e4, move("e7", "e5"))
    assert SAN.parse(after_e5, "Bc4") == {:ok, move("f1", "c4")}

    queen =
      Position.new()
      |> Position.put_piece(square("a1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("d1"), {:white, :queen})

    assert SAN.format(queen, move("d1", "h5")) == {:ok, "Qh5"}
    assert SAN.parse(queen, "Qh5") == {:ok, move("d1", "h5")}

    rook =
      Position.new()
      |> Position.put_piece(square("a1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})

    assert SAN.format(rook, move("h1", "h3")) == {:ok, "Rh3"}
    assert SAN.parse(rook, "Rh3") == {:ok, move("h1", "h3")}

    king =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})

    assert SAN.format(king, move("e1", "e2")) == {:ok, "Ke2"}
    assert SAN.parse(king, "Ke2") == {:ok, move("e1", "e2")}
  end

  test "uses only legal competitors for piece SAN disambiguation" do
    knights =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("b1"), {:white, :knight})
      |> Position.put_piece(square("f1"), {:white, :knight})

    assert SAN.parse(knights, "Nbd2") == {:ok, move("b1", "d2")}
    assert SAN.parse(knights, "Nfd2") == {:ok, move("f1", "d2")}
    assert SAN.parse(knights, "Nd2") == {:error, :invalid_san}
    assert SAN.parse(knights, "Nb1d2") == {:error, :invalid_san}

    rooks =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("a1"), {:white, :rook})
      |> Position.put_piece(square("a3"), {:white, :rook})

    assert SAN.parse(rooks, "R1a2") == {:ok, move("a1", "a2")}
    assert SAN.parse(rooks, "R3a2") == {:ok, move("a3", "a2")}
    assert SAN.parse(rooks, "Ra2") == {:error, :invalid_san}

    both =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("b1"), {:white, :knight})
      |> Position.put_piece(square("b3"), {:white, :knight})
      |> Position.put_piece(square("f1"), {:white, :knight})

    assert SAN.parse(both, "Nb1d2") == {:ok, move("b1", "d2")}
    assert SAN.parse(both, "Nbd2") == {:error, :invalid_san}

    pinned =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e2"), {:white, :knight})
      |> Position.put_piece(square("c2"), {:white, :knight})
      |> Position.put_piece(square("e8"), {:black, :rook})
      |> Position.put_piece(square("a8"), {:black, :king})

    assert SAN.parse(pinned, "Nd4") == {:ok, move("c2", "d4")}
    assert SAN.parse(pinned, "Ncd4") == {:error, :invalid_san}
  end

  test "keeps piece captures, checkmate and castling canonical" do
    capture =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e8"), {:black, :king})
      |> Position.put_piece(square("f3"), {:white, :knight})
      |> Position.put_piece(square("e5"), {:black, :pawn})

    assert SAN.parse(capture, "Nxe5") == {:ok, move("f3", "e5")}
    assert SAN.parse(capture, "Ne5") == {:error, :invalid_san}

    mate =
      Position.new()
      |> Position.put_piece(square("f6"), {:white, :king})
      |> Position.put_piece(square("g6"), {:white, :queen})
      |> Position.put_piece(square("h8"), {:black, :king})

    assert SAN.parse(mate, "Qg7#") == {:ok, move("g6", "g7")}
    assert SAN.parse(mate, "Qg7+") == {:error, :invalid_san}

    castle =
      Position.new(castling_rights: MapSet.new([:white_kingside]))
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :king})

    assert SAN.parse(castle, "O-O") == {:ok, move("e1", "g1")}
    assert SAN.parse(castle, "Kg1") == {:error, :invalid_san}
  end

  test "piece parsing agrees with canonical move formatting for representative positions" do
    start = Position.starting_position()
    {:ok, after_e4} = Position.apply_move(start, move("e2", "e4"))
    {:ok, after_e5} = Position.apply_move(after_e4, move("e7", "e5"))
    {:ok, after_nf3} = Position.apply_move(after_e5, move("g1", "f3"))

    positions = [start, after_e4, after_e5, after_nf3]

    for position <- positions do
      canonical =
        position
        |> Position.legal_moves()
        |> Map.new(fn move ->
          {:ok, notation} = SAN.format(position, move)
          {notation, move}
        end)

      for piece <- ["K", "Q", "R", "B", "N"], destination <- 0..63, suffix <- ["", "+", "#"] do
        notation = piece <> Square.to_algebraic(destination) <> suffix

        expected =
          case Map.fetch(canonical, notation) do
            {:ok, move} -> {:ok, move}
            :error -> {:error, :invalid_san}
          end

        assert SAN.parse(position, notation) == expected,
               "Piece SAN mismatch for #{notation} at #{inspect(position)}"
      end
    end
  end

  test "targeted piece parser accepts the exact check and checkmate suffixes" do
    checking =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("a8"), {:black, :king})
      |> Position.put_piece(square("h1"), {:white, :rook})

    assert SAN.parse(checking, "Rh8+") == {:ok, move("h1", "h8")}
    assert SAN.parse(checking, "Rh8") == {:error, :invalid_san}
    assert SAN.parse(checking, "Rh8#") == {:error, :invalid_san}

    mating =
      Position.new()
      |> Position.put_piece(square("f6"), {:white, :king})
      |> Position.put_piece(square("g6"), {:white, :queen})
      |> Position.put_piece(square("h8"), {:black, :king})

    assert SAN.parse(mating, "Qg7#") == {:ok, move("g6", "g7")}
    assert SAN.parse(mating, "Qg7+") == {:error, :invalid_san}
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
