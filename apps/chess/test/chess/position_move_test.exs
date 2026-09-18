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

  describe "capturing the opposing king" do
    test "a pawn cannot capture the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("a1"), {:white, :king})

      move = Move.new(square("e7"), square("e8"))

      assert {:error, :illegal_move} = Position.apply_move(position, move)
    end

    test "a knight cannot capture the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("e6"), {:white, :knight})
        |> Position.put_piece(square("f8"), {:black, :king})
        |> Position.put_piece(square("a1"), {:white, :king})

      move = Move.new(square("e6"), square("f8"))

      assert {:error, :illegal_move} = Position.apply_move(position, move)
    end

    test "a bishop cannot capture the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("b5"), {:white, :bishop})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("a1"), {:white, :king})

      move = Move.new(square("b5"), square("e8"))

      assert {:error, :illegal_move} = Position.apply_move(position, move)
    end

    test "a rook cannot capture the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})
        |> Position.put_piece(square("h1"), {:white, :king})

      move = Move.new(square("a1"), square("a8"))

      assert {:error, :illegal_move} = Position.apply_move(position, move)
    end

    test "a queen cannot capture the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("d8"), {:black, :king})
        |> Position.put_piece(square("a1"), {:white, :king})

      move = Move.new(square("d1"), square("d8"))

      assert {:error, :illegal_move} = Position.apply_move(position, move)
    end

    test "legal_moves does not contain a move capturing the opposing king" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("a1"), {:white, :king})
        |> Position.put_piece(square("a2"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("a2"), square("a8")) in moves
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

    test "e5 d5 creates an en passant opportunity" do
      position = Position.starting_position()

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e2"), square("e4"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("a7"), square("a6"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("e4"), square("e5"))
               )

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("d7"), square("d5"))
               )

      assert position.en_passant == square("d6")
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

    test "white en passant is only available immediately after the double pawn move" do
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

      other_move =
        Move.new(square("d4"), square("d3"))

      assert {:ok, after_other_move} =
               Position.apply_move(after_double_move, other_move)

      assert after_other_move.en_passant == nil

      capture = Move.new(square("d3"), square("e4"))

      assert {:error, :illegal_move} =
               Position.apply_move(after_other_move, capture)
    end

    test "en passant is illegal when it exposes the king to a rook" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      move = Move.new(square("e5"), square("d6"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "black en passant is illegal when it exposes the king to a rook" do
      position =
        Position.new(
          side_to_move: :black,
          en_passant: square("d3")
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e4"), {:black, :pawn})
        |> Position.put_piece(square("d4"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :rook})
        |> Position.put_piece(square("a1"), {:white, :king})

      move = Move.new(square("e4"), square("d3"))

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
    end

    test "legal_moves and apply_move both reject en passant that exposes the king" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      move = Move.new(square("e5"), square("d6"))

      refute move in Position.legal_moves(position)

      assert {:error, :illegal_move} =
               Position.apply_move(position, move)
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

    test "king cannot move to an attacked square" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(position, Move.new(square("e1"), square("e2")))
    end

    test "king can move to a square that is not attacked" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :rook})

      assert {:ok, _position} =
               Position.apply_move(position, Move.new(square("e1"), square("e2")))
    end

    test "king cannot capture onto an attacked square" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:black, :pawn})
        |> Position.put_piece(square("e3"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("e2"))
               )
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

  describe "bishop moves" do
    test "can move diagonally" do
      position =
        Position.new()
        |> Position.put_piece(square("c1"), {:white, :bishop})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("c1"), square("h6"))
               )

      assert Position.piece_at(new_position, square("c1")) == nil
      assert Position.piece_at(new_position, square("h6")) == {:white, :bishop}
    end

    test "cannot move straight" do
      position =
        Position.new()
        |> Position.put_piece(square("c1"), {:white, :bishop})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("c1"), square("c4"))
               )
    end

    test "cannot move through a piece" do
      position =
        Position.new()
        |> Position.put_piece(square("c1"), {:white, :bishop})
        |> Position.put_piece(square("d2"), {:white, :pawn})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("c1"), square("e3"))
               )
    end

    test "cannot capture own piece" do
      position =
        Position.new()
        |> Position.put_piece(square("c1"), {:white, :bishop})
        |> Position.put_piece(square("h6"), {:white, :pawn})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("c1"), square("h6"))
               )
    end

    test "can capture opponent piece" do
      position =
        Position.new()
        |> Position.put_piece(square("c1"), {:white, :bishop})
        |> Position.put_piece(square("h6"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("c1"), square("h6"))
               )

      assert Position.piece_at(new_position, square("h6")) == {:white, :bishop}
    end
  end

  test "cannot make a move that leaves own king in check" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e2"), {:white, :rook})
      |> Position.put_piece(square("e8"), {:black, :rook})

    assert {:error, :illegal_move} =
             Position.apply_move(
               position,
               Move.new(square("e2"), square("d2"))
             )
  end

  test "can make a move when own king remains safe" do
    position =
      Position.new()
      |> Position.put_piece(square("e1"), {:white, :king})
      |> Position.put_piece(square("e2"), {:white, :rook})
      |> Position.put_piece(square("a8"), {:black, :rook})

    assert {:ok, _position} =
             Position.apply_move(
               position,
               Move.new(square("e2"), square("d2"))
             )
  end

  describe "knight moves" do
    test "can move in an L-shape" do
      position =
        Position.new()
        |> Position.put_piece(square("b1"), {:white, :knight})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("b1"), square("c3"))
               )

      assert Position.piece_at(new_position, square("b1")) == nil
      assert Position.piece_at(new_position, square("c3")) == {:white, :knight}
    end

    test "can jump over pieces" do
      position =
        Position.new()
        |> Position.put_piece(square("b1"), {:white, :knight})
        |> Position.put_piece(square("b2"), {:white, :pawn})
        |> Position.put_piece(square("c2"), {:white, :pawn})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("b1"), square("c3"))
               )

      assert Position.piece_at(new_position, square("c3")) == {:white, :knight}
    end

    test "cannot move like a bishop" do
      position =
        Position.new()
        |> Position.put_piece(square("b1"), {:white, :knight})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("b1"), square("d3"))
               )
    end

    test "cannot capture own piece" do
      position =
        Position.new()
        |> Position.put_piece(square("b1"), {:white, :knight})
        |> Position.put_piece(square("c3"), {:white, :pawn})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("b1"), square("c3"))
               )
    end

    test "can capture opponent piece" do
      position =
        Position.new()
        |> Position.put_piece(square("b1"), {:white, :knight})
        |> Position.put_piece(square("c3"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("b1"), square("c3"))
               )

      assert Position.piece_at(new_position, square("c3")) == {:white, :knight}
    end
  end

  describe "queen moves" do
    test "can move horizontally" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("h1"))
               )

      assert Position.piece_at(new_position, square("d1")) == nil
      assert Position.piece_at(new_position, square("h1")) == {:white, :queen}
    end

    test "can move vertically" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("d8"))
               )

      assert Position.piece_at(new_position, square("d1")) == nil
      assert Position.piece_at(new_position, square("d8")) == {:white, :queen}
    end

    test "can move diagonally" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("h5"))
               )

      assert Position.piece_at(new_position, square("d1")) == nil
      assert Position.piece_at(new_position, square("h5")) == {:white, :queen}
    end

    test "cannot move through a piece" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("d4"), {:white, :pawn})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("d8"))
               )
    end

    test "cannot make a knight move" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("e3"))
               )
    end

    test "cannot capture own piece" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("h5"), {:white, :pawn})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("h5"))
               )
    end

    test "can capture opponent piece" do
      position =
        Position.new()
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("h5"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d1"), square("h5"))
               )

      assert Position.piece_at(new_position, square("h5")) == {:white, :queen}
    end
  end

  describe "castling" do
    test "can castle kingside" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )

      assert Position.piece_at(new_position, square("e1")) == nil
      assert Position.piece_at(new_position, square("g1")) == {:white, :king}
      assert Position.piece_at(new_position, square("h1")) == nil
      assert Position.piece_at(new_position, square("f1")) == {:white, :rook}
      refute MapSet.member?(new_position.castling_rights, :white_kingside)
    end

    test "can castle queenside" do
      position =
        Position.new(castling_rights: MapSet.new([:white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("c1"))
               )

      assert Position.piece_at(new_position, square("e1")) == nil
      assert Position.piece_at(new_position, square("c1")) == {:white, :king}
      assert Position.piece_at(new_position, square("a1")) == nil
      assert Position.piece_at(new_position, square("d1")) == {:white, :rook}
      refute MapSet.member?(new_position.castling_rights, :white_queenside)
    end

    test "cannot castle without the castling right" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )
    end

    test "cannot castle when a square between king and rook is occupied" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("f1"), {:white, :bishop})
        |> Position.put_piece(square("h1"), {:white, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )
    end

    test "cannot castle while in check" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )
    end

    test "cannot castle through an attacked square" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("f8"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )
    end

    test "cannot castle onto an attacked square" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("g8"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("g1"))
               )
    end

    test "king loses both castling rights when it moves" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside, :white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("e1"), square("e2"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_kingside)
      refute MapSet.member?(new_position.castling_rights, :white_queenside)
    end

    test "rook loses kingside castling right when it moves" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("h1"), square("g1"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_kingside)
    end

    test "loses white kingside castling right when the h1 rook is captured" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_kingside])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("h8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("h8"), square("h1"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_kingside)
    end

    test "loses white queenside castling right when the a1 rook is captured" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_queenside])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("a8"), square("a1"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_queenside)
    end

    test "loses black kingside castling right when the h8 rook is captured" do
      position =
        Position.new(
          side_to_move: :white,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("h1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("h1"), square("h8"))
               )

      refute MapSet.member?(new_position.castling_rights, :black_kingside)
    end

    test "loses black queenside castling right when the a8 rook is captured" do
      position =
        Position.new(
          side_to_move: :white,
          castling_rights: MapSet.new([:black_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("a8"), {:black, :rook})
        |> Position.put_piece(square("a1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("a1"), square("a8"))
               )

      refute MapSet.member?(new_position.castling_rights, :black_queenside)
    end

    test "black can castle kingside" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("g8"))
               )

      assert Position.piece_at(new_position, square("e8")) == nil
      assert Position.piece_at(new_position, square("g8")) == {:black, :king}
      assert Position.piece_at(new_position, square("h8")) == nil
      assert Position.piece_at(new_position, square("f8")) == {:black, :rook}

      refute MapSet.member?(new_position.castling_rights, :black_kingside)
    end

    test "black can castle queenside" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("a8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("c8"))
               )

      assert Position.piece_at(new_position, square("e8")) == nil
      assert Position.piece_at(new_position, square("c8")) == {:black, :king}
      assert Position.piece_at(new_position, square("a8")) == nil
      assert Position.piece_at(new_position, square("d8")) == {:black, :rook}

      refute MapSet.member?(new_position.castling_rights, :black_queenside)
    end

    test "black cannot castle while in check" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("e1"), {:white, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("g8"))
               )
    end

    test "black cannot castle through an attacked square" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("f1"), {:white, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("g8"))
               )
    end

    test "black cannot castle onto an attacked square" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("g1"), {:white, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("g8"))
               )
    end

    test "black cannot castle when a square between king and rook is occupied" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("f8"), {:black, :bishop})
        |> Position.put_piece(square("h8"), {:black, :rook})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e8"), square("g8"))
               )
    end

    test "moving the queenside rook preserves the kingside castling right" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside, :white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("a1"), square("a2"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_queenside)
      assert MapSet.member?(new_position.castling_rights, :white_kingside)
    end

    test "capturing the queenside rook preserves the kingside castling right" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_kingside, :white_queenside])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("a8"), square("a1"))
               )

      refute MapSet.member?(new_position.castling_rights, :white_queenside)
      assert MapSet.member?(new_position.castling_rights, :white_kingside)
    end

    test "moving a rook that is not on its original square preserves castling rights" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside, :white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d2"), {:white, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d2"), square("d3"))
               )

      assert MapSet.equal?(
               new_position.castling_rights,
               MapSet.new([:white_kingside, :white_queenside])
             )
    end

    test "capturing a rook that is not on its original square preserves castling rights" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_kingside, :white_queenside])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d2"), {:white, :rook})
        |> Position.put_piece(square("d8"), {:black, :rook})

      assert {:ok, new_position} =
               Position.apply_move(
                 position,
                 Move.new(square("d8"), square("d2"))
               )

      assert MapSet.equal?(
               new_position.castling_rights,
               MapSet.new([:white_kingside, :white_queenside])
             )
    end
  end

  describe "castling rights after castling" do
    test "kingside castling removes both white castling rights" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside, :white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e1"), square("g1"))
        )

      assert position.castling_rights == MapSet.new()
    end

    test "queenside castling removes both white castling rights" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside, :white_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e1"), square("c1"))
        )

      assert position.castling_rights == MapSet.new()
    end

    test "kingside castling removes both black castling rights" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside, :black_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e8"), square("g8"))
        )

      assert position.castling_rights == MapSet.new()
    end

    test "queenside castling removes both black castling rights" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:black_kingside, :black_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("a8"), {:black, :rook})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e8"), square("c8"))
        )

      assert position.castling_rights == MapSet.new()
    end
  end

  describe "castling rights after promotion capture" do
    test "white promotion capture on a8 removes black queenside castling rights" do
      position =
        Position.new(castling_rights: MapSet.new([:black_kingside, :black_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("b7"), {:white, :pawn})
        |> Position.put_piece(square("a8"), {:black, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("b7"), square("a8"), :queen)
        )

      assert position.castling_rights == MapSet.new([:black_kingside])
    end

    test "white promotion capture on h8 removes black kingside castling rights" do
      position =
        Position.new(castling_rights: MapSet.new([:black_kingside, :black_queenside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("g7"), {:white, :pawn})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("e8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("g7"), square("h8"), :queen)
        )

      assert position.castling_rights == MapSet.new([:black_queenside])
    end

    test "black promotion capture on a1 removes white queenside castling rights" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_kingside, :white_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("b2"), {:black, :pawn})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("b2"), square("a1"), :queen)
        )

      assert position.castling_rights == MapSet.new([:white_kingside])
    end

    test "black promotion capture on h1 removes white kingside castling rights" do
      position =
        Position.new(
          side_to_move: :black,
          castling_rights: MapSet.new([:white_kingside, :white_queenside])
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("g2"), {:black, :pawn})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("g2"), square("h1"), :queen)
        )

      assert position.castling_rights == MapSet.new([:white_queenside])
    end
  end

  describe "legal_moves/1 and apply_move/2 consistency" do
    test "every legal move from the starting position can be applied" do
      position = Position.starting_position()

      assert_all_legal_moves_can_be_applied(position)
    end

    test "every legal move in a middlegame position can be applied" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("g1"), {:white, :knight})
        |> Position.put_piece(square("c1"), {:white, :bishop})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("a2"), {:white, :pawn})
        |> Position.put_piece(square("b2"), {:white, :pawn})
        |> Position.put_piece(square("c2"), {:white, :pawn})
        |> Position.put_piece(square("d4"), {:white, :pawn})
        |> Position.put_piece(square("f2"), {:white, :pawn})
        |> Position.put_piece(square("g2"), {:white, :pawn})
        |> Position.put_piece(square("h2"), {:white, :pawn})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("g8"), {:black, :knight})
        |> Position.put_piece(square("c8"), {:black, :bishop})
        |> Position.put_piece(square("a8"), {:black, :rook})
        |> Position.put_piece(square("h8"), {:black, :rook})
        |> Position.put_piece(square("d8"), {:black, :queen})
        |> Position.put_piece(square("a7"), {:black, :pawn})
        |> Position.put_piece(square("b7"), {:black, :pawn})
        |> Position.put_piece(square("c7"), {:black, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("f7"), {:black, :pawn})
        |> Position.put_piece(square("g7"), {:black, :pawn})
        |> Position.put_piece(square("h7"), {:black, :pawn})

      assert_all_legal_moves_can_be_applied(position)
    end

    test "every legal castling move can be applied" do
      for {side, king_from, king_to, rook_from, rook_to, right} <- [
            {:white, "e1", "g1", "h1", "f1", :white_kingside},
            {:white, "e1", "c1", "a1", "d1", :white_queenside},
            {:black, "e8", "g8", "h8", "f8", :black_kingside},
            {:black, "e8", "c8", "a8", "d8", :black_queenside}
          ] do
        position =
          Position.new(
            side_to_move: side,
            castling_rights: MapSet.new([right])
          )
          |> Position.put_piece(square(king_from), {side, :king})
          |> Position.put_piece(square(rook_from), {side, :rook})

        assert_all_legal_moves_can_be_applied(position)

        castle = Move.new(square(king_from), square(king_to))

        assert castle in Position.legal_moves(position)
        assert {:ok, next_position} = Position.apply_move(position, castle)
        assert Position.piece_at(next_position, square(king_to)) == {side, :king}
        assert Position.piece_at(next_position, square(rook_to)) == {side, :rook}
      end
    end

    test "every legal en passant move can be applied" do
      positions = [
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e8"), {:black, :king}),
        Position.new(
          side_to_move: :black,
          en_passant: square("e3")
        )
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("d4"), {:black, :pawn})
        |> Position.put_piece(square("e4"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
      ]

      Enum.each(positions, &assert_all_legal_moves_can_be_applied/1)
    end

    test "every legal promotion move can be applied" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Enum.count(moves, &(&1.from == square("e7"))) == 4
      assert_all_legal_moves_can_be_applied(position)
    end
  end

  describe "state transitions" do
    test "en passant clears the target after the capture" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      move = Move.new(square("e5"), square("d6"))

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("e5")) == nil
      assert Position.piece_at(next, square("d5")) == nil
      assert Position.piece_at(next, square("d6")) == {:white, :pawn}
      assert next.en_passant == nil
      assert next.side_to_move == :black
    end

    test "promotion replaces the pawn and clears en passant" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :king})

      move = Move.new(square("e7"), square("e8"), :knight)

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("e7")) == nil
      assert Position.piece_at(next, square("e8")) == {:white, :knight}
      assert next.en_passant == nil
      assert next.side_to_move == :black
    end

    test "promotion capture replaces the pawn and removes the captured piece" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("d8"), {:black, :bishop})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      move = Move.new(square("e7"), square("d8"), :rook)

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("e7")) == nil
      assert Position.piece_at(next, square("d8")) == {:white, :rook}
      assert next.en_passant == nil
      assert next.side_to_move == :black
    end

    test "castling moves both king and rook and clears all castling state" do
      rights =
        MapSet.new([
          :white_kingside,
          :white_queenside,
          :black_kingside,
          :black_queenside
        ])

      position =
        Position.new(
          side_to_move: :white,
          castling_rights: rights,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("a1"), {:white, :rook})

      move = Move.new(square("e1"), square("g1"))

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("e1")) == nil
      assert Position.piece_at(next, square("h1")) == nil
      assert Position.piece_at(next, square("g1")) == {:white, :king}
      assert Position.piece_at(next, square("f1")) == {:white, :rook}

      assert next.castling_rights ==
               MapSet.new([
                 :black_kingside,
                 :black_queenside
               ])

      assert next.en_passant == nil
      assert next.side_to_move == :black
    end

    test "capturing a rook on its original square clears its castling right" do
      rights =
        MapSet.new([
          :white_kingside,
          :white_queenside,
          :black_kingside,
          :black_queenside
        ])

      position =
        Position.new(
          side_to_move: :white,
          castling_rights: rights
        )
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      move = Move.new(square("a1"), square("a8"))

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("a1")) == nil
      assert Position.piece_at(next, square("a8")) == {:white, :rook}

      assert next.castling_rights ==
               MapSet.new([
                 :white_kingside,
                 :white_queenside,
                 :black_kingside
               ])

      assert next.en_passant == nil
      assert next.side_to_move == :black
    end

    test "promotion capture of a rook clears its castling right" do
      rights =
        MapSet.new([
          :white_kingside,
          :white_queenside,
          :black_kingside,
          :black_queenside
        ])

      position =
        Position.new(
          side_to_move: :white,
          castling_rights: rights
        )
        |> Position.put_piece(square("b7"), {:white, :pawn})
        |> Position.put_piece(square("a8"), {:black, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      move = Move.new(square("b7"), square("a8"), :queen)

      assert {:ok, next} = Position.apply_move(position, move)

      assert Position.piece_at(next, square("b7")) == nil
      assert Position.piece_at(next, square("a8")) == {:white, :queen}

      assert next.castling_rights ==
               MapSet.new([
                 :white_kingside,
                 :white_queenside,
                 :black_kingside
               ])

      assert next.en_passant == nil
      assert next.side_to_move == :black
    end
  end

  defp assert_all_legal_moves_can_be_applied(position) do
    moves = Position.legal_moves(position)

    Enum.each(moves, fn move ->
      assert {:ok, _next_position} = Position.apply_move(position, move)
    end)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
