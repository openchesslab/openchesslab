defmodule Chess.BoardTest do
  use ExUnit.Case

  alias Chess.Square
  alias Chess.Board

  describe "empty/0" do
    test "creates an empty board" do
      board = Board.empty()

      assert tuple_size(board) == 64
      assert Board.pieces(board) == []
    end
  end

  describe "get/2" do
    test "returns nil for an empty square" do
      square = Square.from_algebraic("e4")

      board = Board.empty()

      assert Board.get(board, square) == nil
    end

    test "returns the piece on a square" do
      square = Square.from_algebraic("e4")

      board =
        Board.empty()
        |> Board.put(square, {:white, :pawn})

      assert Board.get(board, square) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      square = Square.from_algebraic("e4")
      board = Board.empty()
      new_board = Board.put(board, square, {:white, :pawn})

      assert Board.get(board, square) == nil
      assert Board.get(new_board, square) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      square = Square.from_algebraic("e4")

      board =
        Board.empty()
        |> Board.put(square, {:white, :pawn})
        |> Board.put(square, {:black, :knight})

      assert Board.get(board, square) == {:black, :knight}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      square = Square.from_algebraic("e4")

      board =
        Board.empty()
        |> Board.put(square, {:white, :pawn})
        |> Board.remove(square)

      assert Board.get(board, square) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces with their squares" do
      e1_square = Square.from_algebraic("e1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      board =
        Board.empty()
        |> Board.put(e1_square, {:white, :king})
        |> Board.put(e4_square, {:white, :pawn})
        |> Board.put(e8_square, {:black, :king})

      assert Enum.sort(Board.pieces(board)) == [
               {e1_square, {:white, :king}},
               {e4_square, {:white, :pawn}},
               {e8_square, {:black, :king}}
             ]
    end
  end
end
