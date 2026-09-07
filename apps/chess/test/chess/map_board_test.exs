defmodule Chess.MapBoardTest do
  use ExUnit.Case

  alias Chess.MapBoard

  describe "empty/0" do
    test "creates an empty board" do
      assert MapBoard.empty() == %{}
    end
  end

  describe "get/2" do
    test "returns nil for an empty square" do
      board = MapBoard.empty()

      assert MapBoard.get(board, 28) == nil
    end

    test "returns the piece on a square" do
      board =
        MapBoard.empty()
        |> MapBoard.put(28, {:white, :pawn})

      assert MapBoard.get(board, 28) == {:white, :pawn}
    end
  end

  describe "put/3" do
    test "does not mutate the original board" do
      board = MapBoard.empty()

      updated = MapBoard.put(board, 28, {:white, :pawn})

      assert MapBoard.get(board, 28) == nil
      assert MapBoard.get(updated, 28) == {:white, :pawn}
    end

    test "replaces an existing piece" do
      board =
        MapBoard.empty()
        |> MapBoard.put(28, {:white, :pawn})

      updated =
        MapBoard.put(board, 28, {:white, :queen})

      assert MapBoard.get(updated, 28) == {:white, :queen}
    end
  end

  describe "remove/2" do
    test "removes a piece" do
      board =
        MapBoard.empty()
        |> MapBoard.put(28, {:white, :pawn})

      updated = MapBoard.remove(board, 28)

      assert MapBoard.get(updated, 28) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces ordered by square" do
      board =
        MapBoard.empty()
        |> MapBoard.put(63, {:black, :king})
        |> MapBoard.put(0, {:white, :rook})
        |> MapBoard.put(28, {:white, :pawn})

      assert MapBoard.pieces(board) == [
               {0, {:white, :rook}},
               {28, {:white, :pawn}},
               {63, {:black, :king}}
             ]
    end
  end
end
