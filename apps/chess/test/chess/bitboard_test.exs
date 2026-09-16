defmodule Chess.BitboardTest do
  use ExUnit.Case

  import Bitwise

  alias Chess.Square
  alias Chess.Bitboard
  alias Chess.Position

  defp bitboard_for(squares) do
    Enum.reduce(squares, 0, fn square, attacks ->
      attacks ||| 1 <<< square(square)
    end)
  end

  defp square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  defp put_piece(board, square, piece) do
    Bitboard.put(board, square(square), piece)
  end

  defp attacks_contains?(attacks, square) do
    (attacks &&& 1 <<< square(square)) != 0
  end

  describe "empty/0" do
    test "creates an empty board" do
      board = Bitboard.empty()

      assert Bitboard.pieces(board) == []
    end
  end

  describe "get/2" do
    test "returns nil for an empty square" do
      board = Bitboard.empty()

      assert Bitboard.get(board, Square.from_algebraic("e4")) == nil
    end

    test "returns the piece on a square" do
      board =
        Bitboard.empty()
        |> Bitboard.put(28, {:white, :pawn})

      assert Bitboard.get(board, Square.from_algebraic("e4")) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      board = Bitboard.empty()
      square = Square.from_algebraic("e4")

      updated = Bitboard.put(board, square, {:white, :pawn})

      assert Bitboard.get(board, square) == nil
      assert Bitboard.get(updated, square) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      square = Square.from_algebraic("e4")

      board =
        Bitboard.empty()
        |> Bitboard.put(square, {:white, :pawn})

      updated =
        Bitboard.put(board, square, {:white, :queen})

      assert Bitboard.get(updated, square) == {:white, :queen}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      square = Square.from_algebraic("e4")

      board =
        Bitboard.empty()
        |> Bitboard.put(square, {:white, :pawn})

      updated = Bitboard.remove(board, square)

      assert Bitboard.get(updated, square) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces ordered by square" do
      a1_square = Square.from_algebraic("a1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      board =
        Bitboard.empty()
        |> Bitboard.put(e8_square, {:black, :king})
        |> Bitboard.put(a1_square, {:white, :rook})
        |> Bitboard.put(e4_square, {:white, :pawn})

      assert Bitboard.pieces(board) == [
               {a1_square, {:white, :rook}},
               {e4_square, {:white, :pawn}},
               {e8_square, {:black, :king}}
             ]
    end
  end

  describe "bit representation" do
    test "sets the correct bit" do
      square = Square.from_algebraic("e4")

      board =
        Bitboard.empty()
        |> Bitboard.put(square, {:white, :pawn})

      assert board.white_pawns == 1 <<< square
    end
  end

  describe "swap_colors/1" do
    test "swaps piece colors without changing squares" do
      a1_square = Square.from_algebraic("a1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      board =
        Bitboard.empty()
        |> Bitboard.put(a1_square, {:white, :rook})
        |> Bitboard.put(e4_square, {:white, :pawn})
        |> Bitboard.put(e8_square, {:black, :king})

      transformed = Bitboard.swap_colors(board)

      assert Bitboard.get(transformed, a1_square) == {:black, :rook}
      assert Bitboard.get(transformed, e4_square) == {:black, :pawn}
      assert Bitboard.get(transformed, e8_square) == {:white, :king}
    end

    test "swapping colors twice returns the original board" do
      a1_square = Square.from_algebraic("a1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      board =
        Bitboard.empty()
        |> Bitboard.put(a1_square, {:white, :rook})
        |> Bitboard.put(e4_square, {:white, :pawn})
        |> Bitboard.put(e8_square, {:black, :king})

      transformed =
        board
        |> Bitboard.swap_colors()
        |> Bitboard.swap_colors()

      assert transformed == board
    end
  end

  describe "from_position/1" do
    test "converts a position to a bitboard" do
      position = Position.starting_position()

      bitboard = Bitboard.from_position(position)

      assert Bitboard.get(bitboard, Square.from_algebraic("e2")) ==
               {:white, :pawn}

      assert Bitboard.get(bitboard, Square.from_algebraic("e7")) ==
               {:black, :pawn}

      assert Bitboard.get(bitboard, Square.from_algebraic("e1")) ==
               {:white, :king}

      assert Bitboard.get(bitboard, Square.from_algebraic("e8")) ==
               {:black, :king}
    end

    test "converts an empty position to an empty bitboard" do
      position = Chess.Position.new()

      assert Bitboard.from_position(position) ==
               Bitboard.empty()
    end
  end

  describe "rook_attacks/2" do
    test "returns horizontal and vertical attacks on an empty board" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.rook_attacks(board, square)

      expected =
        [
          "a4",
          "b4",
          "c4",
          "e4",
          "f4",
          "g4",
          "h4",
          "d1",
          "d2",
          "d3",
          "d5",
          "d6",
          "d7",
          "d8"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "does not include the rook square itself" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.rook_attacks(board, square)

      refute (attacks &&& 1 <<< square) != 0
    end

    test "stops at a blocker" do
      board =
        Bitboard.empty()
        |> put_piece("d6", {:white, :pawn})

      attacks = Bitboard.rook_attacks(board, square("d4"))

      assert attacks_contains?(attacks, "d5")
      assert attacks_contains?(attacks, "d6")
      refute attacks_contains?(attacks, "d7")
      refute attacks_contains?(attacks, "d8")
    end

    test "stops at a blocker horizontally" do
      board =
        Bitboard.empty()
        |> put_piece("f4", {:black, :knight})

      attacks = Bitboard.rook_attacks(board, square("d4"))

      assert attacks_contains?(attacks, "e4")
      assert attacks_contains?(attacks, "f4")
      refute attacks_contains?(attacks, "g4")
      refute attacks_contains?(attacks, "h4")
    end

    test "works from a corner" do
      board = Bitboard.empty()

      attacks = Bitboard.rook_attacks(board, square("a1"))

      expected =
        [
          "b1",
          "c1",
          "d1",
          "e1",
          "f1",
          "g1",
          "h1",
          "a2",
          "a3",
          "a4",
          "a5",
          "a6",
          "a7",
          "a8"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end
  end

  describe "bishop_attacks/2" do
    test "returns diagonal attacks on an empty board" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.bishop_attacks(board, square)

      expected =
        [
          "a1",
          "b2",
          "c3",
          "e3",
          "f2",
          "g1",
          "a7",
          "b6",
          "c5",
          "e5",
          "f6",
          "g7",
          "h8"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "does not include the bishop square itself" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.bishop_attacks(board, square)

      refute (attacks &&& 1 <<< square) != 0
    end

    test "stops at a blocker" do
      board =
        Bitboard.empty()
        |> put_piece("f6", {:white, :pawn})

      attacks = Bitboard.bishop_attacks(board, square("d4"))

      assert attacks_contains?(attacks, "e5")
      assert attacks_contains?(attacks, "f6")
      refute attacks_contains?(attacks, "g7")
      refute attacks_contains?(attacks, "h8")
    end

    test "stops at a blocker in every direction" do
      board =
        Bitboard.empty()
        |> put_piece("b2", {:white, :pawn})
        |> put_piece("f2", {:black, :pawn})
        |> put_piece("b6", {:white, :pawn})
        |> put_piece("f6", {:black, :pawn})

      attacks = Bitboard.bishop_attacks(board, square("d4"))

      assert attacks_contains?(attacks, "c3")
      assert attacks_contains?(attacks, "b2")
      refute attacks_contains?(attacks, "a1")

      assert attacks_contains?(attacks, "e3")
      assert attacks_contains?(attacks, "f2")
      refute attacks_contains?(attacks, "g1")

      assert attacks_contains?(attacks, "c5")
      assert attacks_contains?(attacks, "b6")
      refute attacks_contains?(attacks, "a7")

      assert attacks_contains?(attacks, "e5")
      assert attacks_contains?(attacks, "f6")
      refute attacks_contains?(attacks, "g7")
    end

    test "works from a corner" do
      board = Bitboard.empty()

      attacks = Bitboard.bishop_attacks(board, square("a1"))

      expected =
        [
          "b2",
          "c3",
          "d4",
          "e5",
          "f6",
          "g7",
          "h8"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end
  end

  describe "queen_attacks/2" do
    test "returns rook and bishop attacks on an empty board" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.queen_attacks(board, square)

      expected =
        [
          "a4",
          "b4",
          "c4",
          "e4",
          "f4",
          "g4",
          "h4",
          "d1",
          "d2",
          "d3",
          "d5",
          "d6",
          "d7",
          "d8",
          "a1",
          "b2",
          "c3",
          "e3",
          "f2",
          "g1",
          "a7",
          "b6",
          "c5",
          "e5",
          "f6",
          "g7",
          "h8"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "stops at blockers in all directions" do
      board =
        Bitboard.empty()
        |> put_piece("d6", {:white, :pawn})
        |> put_piece("f4", {:black, :knight})
        |> put_piece("f6", {:white, :pawn})
        |> put_piece("b2", {:black, :pawn})

      attacks = Bitboard.queen_attacks(board, square("d4"))

      assert attacks_contains?(attacks, "d5")
      assert attacks_contains?(attacks, "d6")
      refute attacks_contains?(attacks, "d7")

      assert attacks_contains?(attacks, "e4")
      assert attacks_contains?(attacks, "f4")
      refute attacks_contains?(attacks, "g4")

      assert attacks_contains?(attacks, "e5")
      assert attacks_contains?(attacks, "f6")
      refute attacks_contains?(attacks, "g7")

      assert attacks_contains?(attacks, "c3")
      assert attacks_contains?(attacks, "b2")
      refute attacks_contains?(attacks, "a1")
    end

    test "does not include the queen square itself" do
      board = Bitboard.empty()
      square = square("d4")

      attacks = Bitboard.queen_attacks(board, square)

      refute (attacks &&& 1 <<< square) != 0
    end
  end

  describe "king_attacks/1" do
    test "returns all adjacent squares from the center" do
      attacks = Bitboard.king_attacks(square("d4"))

      expected =
        [
          "c3",
          "d3",
          "e3",
          "c4",
          "e4",
          "c5",
          "d5",
          "e5"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "does not include the king square itself" do
      square = square("d4")
      attacks = Bitboard.king_attacks(square)

      refute (attacks &&& 1 <<< square) != 0
    end

    test "works from a corner" do
      attacks = Bitboard.king_attacks(square("a1"))

      expected =
        ["a2", "b1", "b2"]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "works from an edge" do
      attacks = Bitboard.king_attacks(square("h4"))

      expected =
        [
          "g3",
          "h3",
          "g4",
          "g5",
          "h5"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end
  end

  describe "knight_attacks/1" do
    test "returns all knight attacks from the center" do
      attacks = Bitboard.knight_attacks(square("d4"))

      expected =
        [
          "b3",
          "b5",
          "c2",
          "c6",
          "e2",
          "e6",
          "f3",
          "f5"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "does not include the knight square itself" do
      square = square("d4")
      attacks = Bitboard.knight_attacks(square)

      refute (attacks &&& 1 <<< square) != 0
    end

    test "works from a corner" do
      attacks = Bitboard.knight_attacks(square("a1"))

      expected =
        ["b3", "c2"]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "works from an edge" do
      attacks = Bitboard.knight_attacks(square("h4"))

      expected =
        [
          "f3",
          "f5",
          "g2",
          "g6"
        ]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end
  end

  describe "pawn_attacks/2" do
    test "white pawn attacks diagonally forward" do
      attacks = Bitboard.pawn_attacks(:white, square("d4"))

      expected =
        ["c5", "e5"]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "black pawn attacks diagonally forward" do
      attacks = Bitboard.pawn_attacks(:black, square("d4"))

      expected =
        ["c3", "e3"]
        |> Enum.map(&square/1)
        |> Enum.reduce(0, fn square, attacks ->
          attacks ||| 1 <<< square
        end)

      assert attacks == expected
    end

    test "white pawn from a-file has one attack" do
      attacks = Bitboard.pawn_attacks(:white, square("a4"))

      expected = bitboard_for(["b5"])

      assert attacks == expected
    end

    test "black pawn from a-file has one attack" do
      attacks = Bitboard.pawn_attacks(:black, square("a4"))

      expected = bitboard_for(["b3"])

      assert attacks == expected
    end

    test "white pawn from h-file has one attack" do
      attacks = Bitboard.pawn_attacks(:white, square("h4"))

      expected = bitboard_for(["g5"])

      assert attacks == expected
    end

    test "black pawn from h-file has one attack" do
      attacks = Bitboard.pawn_attacks(:black, square("h4"))

      expected = bitboard_for(["g3"])

      assert attacks == expected
    end

    test "white pawn on eighth rank has no attacks" do
      assert Bitboard.pawn_attacks(:white, square("d8")) == 0
    end

    test "black pawn on first rank has no attacks" do
      assert Bitboard.pawn_attacks(:black, square("d1")) == 0
    end
  end
end
