defmodule Chess.BoardTest do
  use ExUnit.Case

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
      board = Board.empty()

      assert Board.get(board, 28) == nil
    end

    test "returns the piece on a square" do
      board =
        Board.empty()
        |> Board.put(28, {:white, :pawn})

      assert Board.get(board, 28) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      board = Board.empty()
      new_board = Board.put(board, 28, {:white, :pawn})

      assert Board.get(board, 28) == nil
      assert Board.get(new_board, 28) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      board =
        Board.empty()
        |> Board.put(28, {:white, :pawn})
        |> Board.put(28, {:black, :knight})

      assert Board.get(board, 28) == {:black, :knight}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      board =
        Board.empty()
        |> Board.put(28, {:white, :pawn})
        |> Board.remove(28)

      assert Board.get(board, 28) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces with their squares" do
      board =
        Board.empty()
        |> Board.put(4, {:white, :king})
        |> Board.put(28, {:white, :pawn})
        |> Board.put(60, {:black, :king})

      assert Enum.sort(Board.pieces(board)) == [
               {4, {:white, :king}},
               {28, {:white, :pawn}},
               {60, {:black, :king}}
             ]
    end
  end
end
