defmodule Chess.BitboardTest do
  use ExUnit.Case

  import Bitwise

  alias Chess.Square
  alias Chess.Bitboard
  alias Chess.Position

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
end
