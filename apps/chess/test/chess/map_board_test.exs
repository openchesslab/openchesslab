defmodule Chess.MapBoardTest do
  use ExUnit.Case

  alias Chess.Square
  alias Chess.MapBoard

  describe "empty/0" do
    test "creates an empty board" do
      assert MapBoard.empty() == %{}
    end
  end

  describe "get/2" do
    test "returns nil for an empty square" do
      square = Square.from_algebraic("e4")
      board = MapBoard.empty()

      assert MapBoard.get(board, square) == nil
    end

    test "returns the piece on a square" do
      square = Square.from_algebraic("e4")

      board =
        MapBoard.empty()
        |> MapBoard.put(square, {:white, :pawn})

      assert MapBoard.get(board, square) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      square = Square.from_algebraic("e4")

      board = MapBoard.empty()

      updated = MapBoard.put(board, square, {:white, :pawn})

      assert MapBoard.get(board, square) == nil
      assert MapBoard.get(updated, square) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      square = Square.from_algebraic("e4")

      board =
        MapBoard.empty()
        |> MapBoard.put(square, {:white, :pawn})

      updated =
        MapBoard.put(board, square, {:white, :queen})

      assert MapBoard.get(updated, square) == {:white, :queen}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      square = Square.from_algebraic("e4")

      board =
        MapBoard.empty()
        |> MapBoard.put(square, {:white, :pawn})

      updated = MapBoard.remove(board, square)

      assert MapBoard.get(updated, square) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces ordered by square" do
      a1_square = Square.from_algebraic("a1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      board =
        MapBoard.empty()
        |> MapBoard.put(e8_square, {:black, :king})
        |> MapBoard.put(a1_square, {:white, :rook})
        |> MapBoard.put(e4_square, {:white, :pawn})

      assert MapBoard.pieces(board) == [
               {a1_square, {:white, :rook}},
               {e4_square, {:white, :pawn}},
               {e8_square, {:black, :king}}
             ]
    end
  end
end
