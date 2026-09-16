defmodule Chess.PositionMoveTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  describe "apply_move/2" do
    test "moves a pawn two squares from its starting position" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e4"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e2")) == nil
      assert Position.piece_at(next_position, square("e4")) == {:white, :pawn}
    end

    test "changes the side to move" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e4"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert next_position.side_to_move == :black
    end

    test "does not modify the original position" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e4"))

      assert {:ok, _next_position} = Position.apply_move(position, move)

      assert Position.piece_at(position, square("e2")) == {:white, :pawn}
      assert Position.piece_at(position, square("e4")) == nil
    end

    test "rejects an illegal pawn move" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e5"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end
  end

  describe "pawn moves" do
    test "moves one square forward" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e3"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e2")) == nil
      assert Position.piece_at(next_position, square("e3")) == {:white, :pawn}
    end

    test "moves two squares forward from the starting position" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e4"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e2")) == nil
      assert Position.piece_at(next_position, square("e4")) == {:white, :pawn}
    end

    test "white pawn cannot move two squares after leaving its starting rank" do
      position =
        Position.starting_position()
        |> Position.remove_piece(square("e2"))
        |> Position.put_piece(square("e3"), {:white, :pawn})

      move = Move.new(square("e3"), square("e5"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "cannot move three squares forward" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("e5"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "cannot move through another piece" do
      position =
        Position.starting_position()
        |> Position.put_piece(square("e3"), {:white, :knight})

      move = Move.new(square("e2"), square("e4"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "cannot capture a piece directly ahead" do
      position =
        Position.starting_position()
        |> Position.put_piece(square("e3"), {:black, :knight})

      move = Move.new(square("e2"), square("e3"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "can capture diagonally" do
      position =
        Position.starting_position()
        |> Position.put_piece(square("f3"), {:black, :knight})

      move = Move.new(square("e2"), square("f3"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e2")) == nil
      assert Position.piece_at(next_position, square("f3")) == {:white, :pawn}
    end

    test "cannot move diagonally to an empty square" do
      position = Position.starting_position()
      move = Move.new(square("e2"), square("f3"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "black pawn moves one square forward" do
      position =
        Position.starting_position()
        |> Map.put(:side_to_move, :black)

      move = Move.new(square("e7"), square("e6"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e7")) == nil
      assert Position.piece_at(next_position, square("e6")) == {:black, :pawn}
    end

    test "black pawn moves two squares from the starting position" do
      position =
        Position.starting_position()
        |> Map.put(:side_to_move, :black)

      move = Move.new(square("e7"), square("e5"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e7")) == nil
      assert Position.piece_at(next_position, square("e5")) == {:black, :pawn}
    end

    test "black pawn cannot move two squares after leaving its starting rank" do
      position =
        Position.starting_position()
        |> Position.remove_piece(square("e7"))
        |> Position.put_piece(square("e6"), {:black, :pawn})
        |> Map.put(:side_to_move, :black)

      move = Move.new(square("e6"), square("e4"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "black pawn can capture diagonally" do
      position =
        Position.starting_position()
        |> Map.put(:side_to_move, :black)
        |> Position.put_piece(square("d6"), {:white, :knight})

      move = Move.new(square("e7"), square("d6"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e7")) == nil
      assert Position.piece_at(next_position, square("d6")) == {:black, :pawn}
    end
  end

  describe "pawn promotion" do
    test "promotes a white pawn to a queen" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e7"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e7"), square("e8"), :queen)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e7")) == nil
      assert Position.piece_at(next_position, square("e8")) == {:white, :queen}
    end

    test "promotes a white pawn to a rook" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e7"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e7"), square("e8"), :rook)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e8")) == {:white, :rook}
    end

    test "promotes a white pawn to a bishop" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e7"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e7"), square("e8"), :bishop)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e8")) == {:white, :bishop}
    end

    test "promotes a white pawn to a knight" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e7"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e7"), square("e8"), :knight)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e8")) == {:white, :knight}
    end

    test "white pawn cannot promote before reaching the last rank" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e6"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e6"), square("e7"), :queen)

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "promotes a black pawn to a queen" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e2"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("e2"), square("e1"), :queen)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e1")) == {:black, :queen}
    end

    test "promotes a black pawn to a rook" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e2"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("e2"), square("e1"), :rook)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e1")) == {:black, :rook}
    end

    test "promotes a black pawn to a bishop" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e2"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("e2"), square("e1"), :bishop)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e1")) == {:black, :bishop}
    end

    test "promotes a black pawn to a knight" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e2"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("e2"), square("e1"), :knight)

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e1")) == {:black, :knight}
    end

    test "black pawn cannot promote before reaching the last rank" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e3"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("e3"), square("e2"), :queen)

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "a pawn reaching the last rank without promotion is illegal" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e7"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("e7"), square("e8"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end
  end

  describe "en passant" do
    test "a double pawn move creates an en passant target when capture is possible" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e5"), {:white, :pawn})
            |> Chess.Board.put(square("d7"), {:black, :pawn}),
          side_to_move: :black
        )

      move = Move.new(square("d7"), square("d5"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert next_position.en_passant == square("d6")
    end

    test "e4 e5 does not create an en passant opportunity" do
      position = Position.starting_position()

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e2"), square("e4"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e7"), square("e5"))
               )

      assert position.en_passant == nil
    end

    test "e3 e6 e4 e5 does not create an en passant opportunity" do
      position = Position.starting_position()

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e2"), square("e3"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e7"), square("e6"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e3"), square("e4"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e6"), square("e5"))
               )

      assert position.en_passant == nil
    end

    test "a black pawn can capture en passant" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e5"), {:white, :pawn})
            |> Chess.Board.put(square("d7"), {:black, :pawn}),
          side_to_move: :black
        )

      double_move = Move.new(square("d7"), square("d5"))

      assert {:ok, after_double_move} =
               Position.apply_move(position, double_move)

      assert after_double_move.en_passant == square("d6")

      capture = Move.new(square("e5"), square("d6"))

      assert {:ok, next_position} =
               Position.apply_move(after_double_move, capture)

      assert Position.piece_at(next_position, square("e5")) == nil
      assert Position.piece_at(next_position, square("d5")) == nil
      assert Position.piece_at(next_position, square("d6")) == {:white, :pawn}
    end

    test "a white pawn can capture en passant" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:black, :pawn})
            |> Chess.Board.put(square("e2"), {:white, :pawn}),
          side_to_move: :white
        )

      double_move = Move.new(square("e2"), square("e4"))

      assert {:ok, after_double_move} =
               Position.apply_move(position, double_move)

      assert after_double_move.en_passant == square("e3")

      capture = Move.new(square("d4"), square("e3"))

      assert {:ok, next_position} =
               Position.apply_move(after_double_move, capture)

      assert Position.piece_at(next_position, square("d4")) == nil
      assert Position.piece_at(next_position, square("e4")) == nil
      assert Position.piece_at(next_position, square("e3")) == {:black, :pawn}
    end

    test "en passant is only available immediately after the double pawn move" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e5"), {:white, :pawn})
            |> Chess.Board.put(square("d7"), {:black, :pawn})
            |> Chess.Board.put(square("a8"), {:black, :rook}),
          side_to_move: :black
        )

      double_move = Move.new(square("d7"), square("d5"))

      assert {:ok, after_double_move} =
               Position.apply_move(position, double_move)

      assert after_double_move.en_passant == square("d6")

      other_move = Move.new(square("e5"), square("e6"))

      assert {:ok, after_other_move} =
               Position.apply_move(after_double_move, other_move)

      assert after_other_move.en_passant == nil

      capture = Move.new(square("e6"), square("d7"))

      assert {:error, :illegal_move} =
               Position.apply_move(after_other_move, capture)
    end
  end

  describe "king moves" do
    test "king can move one square horizontally" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("f4"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e4")) == nil
      assert Position.piece_at(next_position, square("f4")) == {:white, :king}
      assert next_position.side_to_move == :black
    end

    test "king can move one square vertically" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("e5"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e5")) == {:white, :king}
    end

    test "king can move one square diagonally" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("f5"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("f5")) == {:white, :king}
    end

    test "king cannot move more than one square" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("e6"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "king can capture an opposing piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king})
            |> Chess.Board.put(square("f5"), {:black, :knight}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("f5"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("e4")) == nil
      assert Position.piece_at(next_position, square("f5")) == {:white, :king}
    end

    test "king cannot move onto a friendly piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king})
            |> Chess.Board.put(square("f5"), {:white, :knight}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("f5"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "king cannot move with a promotion" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("e4"), {:white, :king}),
          side_to_move: :white
        )

      move = Move.new(square("e4"), square("e5"), :queen)

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end
  end

  describe "rook moves" do
    test "rook can move horizontally" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("h4"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("d4")) == nil
      assert Position.piece_at(next_position, square("h4")) == {:white, :rook}
      assert next_position.side_to_move == :black
    end

    test "rook can move vertically" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d8"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("d8")) == {:white, :rook}
    end

    test "rook cannot move diagonally" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("e5"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "rook can capture an opposing piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook})
            |> Chess.Board.put(square("d7"), {:black, :knight}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d7"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("d4")) == nil
      assert Position.piece_at(next_position, square("d7")) == {:white, :rook}
    end

    test "rook cannot move onto a friendly piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook})
            |> Chess.Board.put(square("d7"), {:white, :knight}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d7"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "rook cannot jump over a piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook})
            |> Chess.Board.put(square("d6"), {:white, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d8"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "rook can capture the first opposing piece in its path" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook})
            |> Chess.Board.put(square("d6"), {:black, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d6"))

      assert {:ok, next_position} = Position.apply_move(position, move)

      assert Position.piece_at(next_position, square("d4")) == nil
      assert Position.piece_at(next_position, square("d6")) == {:white, :rook}
    end

    test "rook cannot move beyond an opposing piece" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook})
            |> Chess.Board.put(square("d6"), {:black, :pawn}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d8"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "rook cannot move with a promotion" do
      position =
        Position.new(
          board:
            Chess.Board.empty()
            |> Chess.Board.put(square("d4"), {:white, :rook}),
          side_to_move: :white
        )

      move = Move.new(square("d4"), square("d8"), :queen)

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
