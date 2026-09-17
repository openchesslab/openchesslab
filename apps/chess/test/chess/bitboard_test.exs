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

  defp destinations(moves, from_algebraic) do
    moves
    |> Enum.into(%{})
    |> Map.fetch!(square(from_algebraic))
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

  describe "attacked?/3" do
    test "detects a pawn attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :pawn})

      assert Bitboard.attacked?(board, :white, square("e5"))
      refute Bitboard.attacked?(board, :black, square("e5"))
    end

    test "detects a knight attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :knight})

      assert Bitboard.attacked?(board, :white, square("e6"))
      refute Bitboard.attacked?(board, :white, square("e5"))
    end

    test "detects a king attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:black, :king})

      assert Bitboard.attacked?(board, :black, square("e5"))
      refute Bitboard.attacked?(board, :black, square("f6"))
    end

    test "detects a rook attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :rook})

      assert Bitboard.attacked?(board, :white, square("d7"))
      refute Bitboard.attacked?(board, :white, square("e7"))
    end

    test "detects a bishop attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:black, :bishop})

      assert Bitboard.attacked?(board, :black, square("g7"))
      refute Bitboard.attacked?(board, :black, square("g6"))
    end

    test "detects a queen attack" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :queen})

      assert Bitboard.attacked?(board, :white, square("d8"))
      assert Bitboard.attacked?(board, :white, square("h8"))
      refute Bitboard.attacked?(board, :white, square("e7"))
    end

    test "respects blockers for sliding pieces" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :rook})
        |> put_piece("d6", {:white, :pawn})

      assert Bitboard.attacked?(board, :white, square("d5"))
      assert Bitboard.attacked?(board, :white, square("d6"))
      refute Bitboard.attacked?(board, :white, square("d7"))
    end

    test "does not consider attacks from the opposite color" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:black, :rook})

      refute Bitboard.attacked?(board, :white, square("d7"))
      assert Bitboard.attacked?(board, :black, square("d7"))
    end

    test "an empty board has no attacks" do
      board = Bitboard.empty()

      refute Bitboard.attacked?(board, :white, square("d4"))
      refute Bitboard.attacked?(board, :black, square("d4"))
    end
  end

  describe "pseudo_moves/2" do
    test "bishop does not move through a friendly piece" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :bishop})
        |> put_piece("e5", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d4") ==
               bitboard_for([
                 "a1",
                 "b2",
                 "c3",
                 "e3",
                 "f2",
                 "g1",
                 "c5",
                 "b6",
                 "a7"
               ])
    end

    test "rook does not move through a friendly piece" do
      board =
        Bitboard.empty()
        |> put_piece("d5", {:white, :rook})
        |> put_piece("f5", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d5") ==
               bitboard_for([
                 "a5",
                 "b5",
                 "c5",
                 "e5",
                 "d1",
                 "d2",
                 "d3",
                 "d4",
                 "d6",
                 "d7",
                 "d8"
               ])
    end

    test "queen includes the blocker when it is an enemy piece, then stops" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :queen})
        |> put_piece("f4", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert Enum.into(moves, %{}) == %{
               square("d4") =>
                 bitboard_for([
                   "a4",
                   "b4",
                   "c4",
                   "e4",
                   "f4",
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
                 ])
             }
    end

    test "pawn moves one square forward" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e4") ==
               bitboard_for(["e5"])
    end

    test "pawn moves two squares from the starting rank" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e2") ==
               bitboard_for(["e3", "e4"])
    end

    test "white pawn cannot make a double move from a non-starting rank" do
      board =
        Bitboard.empty()
        |> put_piece("e3", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e3") ==
               bitboard_for(["e4"])
    end

    test "black pawn cannot make a double move from a non-starting rank" do
      board =
        Bitboard.empty()
        |> put_piece("e6", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :black)

      assert destinations(moves, "e6") ==
               bitboard_for(["e5"])
    end

    test "pawn cannot move forward through an occupied square" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})
        |> put_piece("e3", {:black, :knight})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e2") == 0
    end

    test "pawn cannot make a double move when the intermediate square is occupied" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})
        |> put_piece("e3", {:black, :knight})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e2") == 0
    end

    test "pawn captures diagonally" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :pawn})
        |> put_piece("d5", {:black, :bishop})
        |> put_piece("f5", {:black, :knight})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e4") ==
               bitboard_for(["e5", "d5", "f5"])
    end

    test "pawn cannot capture a friendly piece" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :pawn})
        |> put_piece("d5", {:white, :bishop})
        |> put_piece("f5", {:white, :knight})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e4") ==
               bitboard_for(["e5"])
    end

    test "pawn cannot move diagonally to an empty square" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "e4") ==
               bitboard_for(["e5"])
    end

    test "white pawn on a-file only attacks towards b-file" do
      board =
        Bitboard.empty()
        |> put_piece("a4", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "a4") ==
               bitboard_for(["a5"])
    end

    test "white pawn on h-file only attacks towards g-file" do
      board =
        Bitboard.empty()
        |> put_piece("h4", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "h4") ==
               bitboard_for(["h5"])
    end

    test "black pawn on a-file only attacks towards b-file" do
      board =
        Bitboard.empty()
        |> put_piece("a5", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :black)

      assert destinations(moves, "a5") ==
               bitboard_for(["a4"])
    end

    test "black pawn on h-file only attacks towards g-file" do
      board =
        Bitboard.empty()
        |> put_piece("h5", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :black)

      assert destinations(moves, "h5") ==
               bitboard_for(["h4"])
    end

    test "black pawn moves towards rank one" do
      board =
        Bitboard.empty()
        |> put_piece("e7", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :black)

      assert destinations(moves, "e7") ==
               bitboard_for(["e6", "e5"])
    end

    test "knight cannot move to a friendly occupied square" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :knight})
        |> put_piece("e6", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d4") ==
               bitboard_for([
                 "b3",
                 "b5",
                 "c2",
                 "c6",
                 "e2",
                 "f3",
                 "f5"
               ])
    end

    test "knight can capture an enemy piece" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :knight})
        |> put_piece("e6", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d4") ==
               bitboard_for([
                 "b3",
                 "b5",
                 "c2",
                 "c6",
                 "e2",
                 "e6",
                 "f3",
                 "f5"
               ])
    end

    test "king cannot move to a friendly occupied square" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :king})
        |> put_piece("e5", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d4") ==
               bitboard_for([
                 "c3",
                 "d3",
                 "e3",
                 "c4",
                 "e4",
                 "c5",
                 "d5"
               ])
    end

    test "king can capture an enemy piece" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :king})
        |> put_piece("e5", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)

      assert destinations(moves, "d4") ==
               bitboard_for([
                 "c3",
                 "d3",
                 "e3",
                 "c4",
                 "e4",
                 "c5",
                 "d5",
                 "e5"
               ])
    end

    test "does not include friendly occupied squares" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :rook})
        |> put_piece("d6", {:white, :pawn})
        |> put_piece("f4", {:white, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)
      attacks = Map.fetch!(Enum.into(moves, %{}), square("d4"))

      refute attacks_contains?(attacks, "d6")
      refute attacks_contains?(attacks, "f4")
      assert attacks_contains?(attacks, "d5")
      assert attacks_contains?(attacks, "e4")
    end

    test "includes enemy pieces as capture destinations" do
      board =
        Bitboard.empty()
        |> put_piece("d4", {:white, :rook})
        |> put_piece("d6", {:black, :pawn})
        |> put_piece("f4", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)
      attacks = Map.fetch!(Enum.into(moves, %{}), square("d4"))

      assert attacks_contains?(attacks, "d6")
      assert attacks_contains?(attacks, "f4")
      refute attacks_contains?(attacks, "d7")
      refute attacks_contains?(attacks, "g4")
    end

    test "generates white pawn pushes and captures" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})
        |> put_piece("d3", {:black, :knight})
        |> put_piece("f3", {:black, :bishop})

      moves = Bitboard.pseudo_moves(board, :white)
      attacks = Map.fetch!(Enum.into(moves, %{}), square("e2"))

      assert attacks == bitboard_for(["e3", "e4", "d3", "f3"])
    end

    test "generates black pawn pushes and captures" do
      board =
        Bitboard.empty()
        |> put_piece("e7", {:black, :pawn})
        |> put_piece("d6", {:white, :knight})
        |> put_piece("f6", {:white, :bishop})

      moves = Bitboard.pseudo_moves(board, :black)
      attacks = Map.fetch!(Enum.into(moves, %{}), square("e7"))

      assert attacks == bitboard_for(["e6", "e5", "d6", "f6"])
    end

    test "pawn cannot move through or onto an occupied square" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})
        |> put_piece("e3", {:black, :pawn})

      moves = Bitboard.pseudo_moves(board, :white)
      attacks = Map.fetch!(Enum.into(moves, %{}), square("e2"))

      assert attacks == 0
    end

    test "returns only pieces of the requested color" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :rook})
        |> put_piece("e5", {:black, :rook})

      moves = Bitboard.pseudo_moves(board, :white)

      assert Enum.map(moves, &elem(&1, 0)) == [square("e4")]
    end

    test "returns an empty list when the color has no pieces" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:black, :rook})

      assert Bitboard.pseudo_moves(board, :white) == []
    end
  end

  describe "after_move/3" do
    test "moves a piece to an empty square" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})

      move = Chess.Move.new(square("e2"), square("e4"))

      updated = Bitboard.after_move(board, move, {:white, :pawn})

      assert Bitboard.get(updated, square("e2")) == nil
      assert Bitboard.get(updated, square("e4")) == {:white, :pawn}
    end

    test "captures a piece on the destination square" do
      board =
        Bitboard.empty()
        |> put_piece("e4", {:white, :bishop})
        |> put_piece("h7", {:black, :pawn})

      move = Chess.Move.new(square("e4"), square("h7"))

      updated = Bitboard.after_move(board, move, {:white, :bishop})

      assert Bitboard.get(updated, square("e4")) == nil
      assert Bitboard.get(updated, square("h7")) == {:white, :bishop}
    end

    test "promotes a pawn" do
      board =
        Bitboard.empty()
        |> put_piece("e7", {:white, :pawn})

      move = Chess.Move.new(square("e7"), square("e8"), :queen)

      updated = Bitboard.after_move(board, move, {:white, :pawn})

      assert Bitboard.get(updated, square("e7")) == nil
      assert Bitboard.get(updated, square("e8")) == {:white, :queen}
    end

    test "does not modify the original board" do
      board =
        Bitboard.empty()
        |> put_piece("e2", {:white, :pawn})

      move = Chess.Move.new(square("e2"), square("e4"))

      updated = Bitboard.after_move(board, move, {:white, :pawn})

      assert Bitboard.get(board, square("e2")) == {:white, :pawn}
      assert Bitboard.get(board, square("e4")) == nil
      assert Bitboard.get(updated, square("e2")) == nil
      assert Bitboard.get(updated, square("e4")) == {:white, :pawn}
    end
  end
end
