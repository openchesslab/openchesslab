defmodule Chess.BoardTest do
  use ExUnit.Case

  alias Chess.Board
  alias Chess.Square

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

      board = Board.put(Board.empty(), square, {:white, :pawn})

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
    test "lists occupied squares in ascending order" do
      board =
        Board.empty()
        |> Board.put(63, {:black, :king})
        |> Board.put(0, {:white, :rook})
        |> Board.put(19, {:white, :bishop})

      assert Board.pieces(board) == [
               {0, {:white, :rook}},
               {19, {:white, :bishop}},
               {63, {:black, :king}}
             ]
    end

    test "matches direct square enumeration on sparse and dense boards" do
      for stride <- [1, 2, 3, 5, 8, 64] do
        board =
          Enum.reduce(0..63, Board.empty(), fn square, acc ->
            if rem(square, stride) == 0 do
              piece =
                if rem(square, 2) == 0,
                  do: {:white, :knight},
                  else: {:black, :pawn}

              Board.put(acc, square, piece)
            else
              acc
            end
          end)

        expected =
          for square <- 0..63,
              piece = Board.get(board, square),
              not is_nil(piece),
              do: {square, piece}

        assert Board.pieces(board) == expected
      end
    end

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
