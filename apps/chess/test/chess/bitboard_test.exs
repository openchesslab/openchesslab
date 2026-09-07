defmodule Chess.BitboardTest do
  use ExUnit.Case

  import Bitwise

  alias Chess.Bitboard

  describe "empty/0" do
    test "creates an empty board" do
      board = Bitboard.empty()

      assert Bitboard.pieces(board) == []
    end
  end

  describe "get/2" do
    test "returns nil for an empty square" do
      board = Bitboard.empty()

      assert Bitboard.get(board, 28) == nil
    end

    test "returns the piece on a square" do
      board =
        Bitboard.empty()
        |> Bitboard.put(28, {:white, :pawn})

      assert Bitboard.get(board, 28) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      board = Bitboard.empty()

      updated = Bitboard.put(board, 28, {:white, :pawn})

      assert Bitboard.get(board, 28) == nil
      assert Bitboard.get(updated, 28) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      board =
        Bitboard.empty()
        |> Bitboard.put(28, {:white, :pawn})

      updated =
        Bitboard.put(board, 28, {:white, :queen})

      assert Bitboard.get(updated, 28) == {:white, :queen}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      board =
        Bitboard.empty()
        |> Bitboard.put(28, {:white, :pawn})

      updated = Bitboard.remove(board, 28)

      assert Bitboard.get(updated, 28) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces ordered by square" do
      board =
        Bitboard.empty()
        |> Bitboard.put(63, {:black, :king})
        |> Bitboard.put(0, {:white, :rook})
        |> Bitboard.put(28, {:white, :pawn})

      assert Bitboard.pieces(board) == [
               {0, {:white, :rook}},
               {28, {:white, :pawn}},
               {63, {:black, :king}}
             ]
    end
  end

  describe "bit representation" do
    test "sets the correct bit" do
      board =
        Bitboard.empty()
        |> Bitboard.put(28, {:white, :pawn})

      assert board.white_pawns == 1 <<< 28
    end
  end

  describe "swap_colors/1" do
    test "swaps piece colors without changing squares" do
      board =
        Bitboard.empty()
        |> Bitboard.put(0, {:white, :rook})
        |> Bitboard.put(28, {:white, :pawn})
        |> Bitboard.put(60, {:black, :king})

      transformed = Bitboard.swap_colors(board)

      assert Bitboard.get(transformed, 0) == {:black, :rook}
      assert Bitboard.get(transformed, 28) == {:black, :pawn}
      assert Bitboard.get(transformed, 60) == {:white, :king}
    end

    test "swapping colors twice returns the original board" do
      board =
        Bitboard.empty()
        |> Bitboard.put(0, {:white, :rook})
        |> Bitboard.put(28, {:white, :pawn})
        |> Bitboard.put(60, {:black, :king})

      transformed =
        board
        |> Bitboard.swap_colors()
        |> Bitboard.swap_colors()

      assert transformed == board
    end
  end
end
