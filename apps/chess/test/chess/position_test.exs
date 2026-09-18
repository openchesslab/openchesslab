defmodule Chess.PositionTest do
  use ExUnit.Case

  alias Chess.Move
  alias Chess.Position

  defp square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  describe "new/0" do
    test "creates an empty position" do
      position = Position.new()

      assert position.board == Chess.Board.empty()
      assert position.side_to_move == :white
      assert position.castling_rights == MapSet.new()
      assert position.en_passant == nil
    end
  end

  describe "piece_at/2" do
    test "returns nil for an empty square" do
      position = Position.new()

      assert Position.piece_at(position, 28) == nil
    end

    test "returns the piece on a square" do
      position =
        Position.new()
        |> Position.put_piece(28, {:white, :pawn})

      assert Position.piece_at(position, 28) == {:white, :pawn}
    end
  end

  describe "put_piece/3" do
    test "does not mutate the original position" do
      position = Position.new()

      updated = Position.put_piece(position, 28, {:white, :pawn})

      assert Position.piece_at(position, 28) == nil
      assert Position.piece_at(updated, 28) == {:white, :pawn}
    end
  end

  describe "remove_piece/2" do
    test "removes a piece" do
      position =
        Position.new()
        |> Position.put_piece(28, {:white, :pawn})

      updated = Position.remove_piece(position, 28)

      assert Position.piece_at(updated, 28) == nil
    end
  end

  describe "pieces/1" do
    test "returns all pieces" do
      position =
        Position.new()
        |> Position.put_piece(0, {:white, :rook})
        |> Position.put_piece(28, {:white, :pawn})
        |> Position.put_piece(63, {:black, :king})

      assert Position.pieces(position) == [
               {0, {:white, :rook}},
               {28, {:white, :pawn}},
               {63, {:black, :king}}
             ]
    end
  end

  describe "position identity" do
    test "en passant is part of the position" do
      position1 =
        Position.new(en_passant: nil)

      position2 =
        Position.new(en_passant: 20)

      refute position1 == position2
    end

    test "side to move is part of the position" do
      position1 = Position.new(side_to_move: :white)
      position2 = Position.new(side_to_move: :black)

      refute position1 == position2
    end

    test "castling rights are part of the position" do
      position1 = Position.new()

      position2 =
        Position.new(castling_rights: MapSet.new([:white_kingside]))

      refute position1 == position2
    end
  end

  describe "starting_position/0" do
    test "creates the standard starting position" do
      position = Position.starting_position()

      assert Position.piece_at(position, Chess.Square.from_algebraic("a1")) ==
               {:white, :rook}

      assert Position.piece_at(position, Chess.Square.from_algebraic("e1")) ==
               {:white, :king}

      assert Position.piece_at(position, Chess.Square.from_algebraic("d1")) ==
               {:white, :queen}

      assert Position.piece_at(position, Chess.Square.from_algebraic("a2")) ==
               {:white, :pawn}

      assert Position.piece_at(position, Chess.Square.from_algebraic("a7")) ==
               {:black, :pawn}

      assert Position.piece_at(position, Chess.Square.from_algebraic("e8")) ==
               {:black, :king}

      assert Position.piece_at(position, Chess.Square.from_algebraic("d8")) ==
               {:black, :queen}
    end

    test "has 32 pieces" do
      position = Position.starting_position()

      assert length(Position.pieces(position)) == 32
    end

    test "white moves first" do
      position = Position.starting_position()

      assert position.side_to_move == :white
    end

    test "has all castling rights" do
      position = Position.starting_position()

      assert position.castling_rights ==
               MapSet.new([
                 :white_kingside,
                 :white_queenside,
                 :black_kingside,
                 :black_queenside
               ])
    end

    test "has no en passant target" do
      position = Position.starting_position()

      assert position.en_passant == nil
    end
  end

  describe "in_check?/2" do
    test "white is in check when its king is attacked" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})

      assert Position.in_check?(position, :white)
    end

    test "white is not in check when its king is not attacked" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :rook})

      refute Position.in_check?(position, :white)
    end

    test "black is in check when its king is attacked" do
      position =
        Position.new()
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e1"), {:white, :rook})

      assert Position.in_check?(position, :black)
    end

    test "a blocker can prevent check" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("e4"), {:white, :pawn})

      refute Position.in_check?(position, :white)
    end

    test "white is in check from a bishop" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h4"), {:black, :bishop})

      assert Position.in_check?(position, :white)
    end

    test "white is in check from a queen" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h4"), {:black, :queen})

      assert Position.in_check?(position, :white)
    end

    test "white is in check from a knight" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("f3"), {:black, :knight})

      assert Position.in_check?(position, :white)
    end

    test "white is in check from a pawn" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d2"), {:black, :pawn})

      assert Position.in_check?(position, :white)
    end

    test "white is in check from the opposing king" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:black, :king})

      assert Position.in_check?(position, :white)
    end
  end

  describe "legal_moves/1" do
    test "starting position has 20 legal moves" do
      position = Position.starting_position()

      moves = Position.legal_moves(position)

      assert length(moves) == 20
    end

    test "legal_moves/1 includes all promotion choices" do
      position =
        Position.new()
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), nil)

      moves = Position.legal_moves(position)

      assert Enum.sort(Enum.filter(moves, &(&1.from == square("e7") and &1.to == square("e8")))) ==
               Enum.sort([
                 Move.new(square("e7"), square("e8"), :queen),
                 Move.new(square("e7"), square("e8"), :rook),
                 Move.new(square("e7"), square("e8"), :bishop),
                 Move.new(square("e7"), square("e8"), :knight)
               ])
    end

    test "legal_moves/1 includes all promotion choices for a capture" do
      position =
        Position.new()
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("d8"), {:black, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Enum.sort(Enum.filter(moves, &(&1.from == square("e7") and &1.to == square("d8")))) ==
               Enum.sort([
                 Move.new(square("e7"), square("d8"), :queen),
                 Move.new(square("e7"), square("d8"), :rook),
                 Move.new(square("e7"), square("d8"), :bishop),
                 Move.new(square("e7"), square("d8"), :knight)
               ])
    end

    test "legal_moves/1 includes an en passant capture" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("e5"), square("d6")) in moves
    end

    test "legal_moves/1 includes castling" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})

      moves = Position.legal_moves(position)

      assert Move.new(square("e1"), square("g1")) in moves
    end

    test "legal_moves/1 excludes moves that leave the king in check" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})

      moves = Position.legal_moves(position)

      refute Move.new(square("e2"), square("f2")) in moves
      refute Move.new(square("e2"), square("d2")) in moves
    end

    test "checkmate has no legal moves" do
      position =
        Position.starting_position()

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("f2"), square("f3"))
        )

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e7"), square("e5"))
        )

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("g2"), square("g4"))
        )

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("d8"), square("h4"))
        )

      assert Position.in_check?(position, :white)
      assert Position.legal_moves(position) == []
    end

    test "stalemate has no legal moves" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("h1"), {:white, :king})
        |> Position.put_piece(square("f2"), {:black, :king})
        |> Position.put_piece(square("g3"), {:black, :queen})

      refute Position.in_check?(position, :white)
      assert Position.legal_moves(position) == []
    end

    test "legal_moves/1 generates moves for all piece types" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("c1"), {:white, :bishop})
        |> Position.put_piece(square("b1"), {:white, :knight})
        |> Position.put_piece(square("d1"), {:white, :queen})
        |> Position.put_piece(square("e2"), {:white, :pawn})

      moves = Position.legal_moves(position)

      assert Move.new(square("a1"), square("a2")) in moves
      assert Move.new(square("b1"), square("c3")) in moves
      assert Move.new(square("c1"), square("d2")) in moves
      assert Move.new(square("d1"), square("d2")) in moves
      assert Move.new(square("e2"), square("e3")) in moves
      assert Move.new(square("e1"), square("f1")) in moves
    end

    test "king cannot move into check" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("e5"), {:black, :rook})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e2")) in moves
      assert Move.new(square("e1"), square("f1")) in moves
    end

    test "pinned rook can only move along the pin" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})

      moves = Position.legal_moves(position)

      assert Move.new(square("e2"), square("e3")) in moves
      assert Move.new(square("e2"), square("e8")) in moves

      refute Move.new(square("e2"), square("f2")) in moves
      refute Move.new(square("e2"), square("d2")) in moves
    end

    test "a piece can block a sliding check" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})

      moves = Position.legal_moves(position)

      assert Move.new(square("a1"), square("e1")) not in moves
    end

    test "king can move out of check" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("e1"), square("f1")) in moves
      assert Move.new(square("e1"), square("d1")) in moves
    end

    test "king can capture the checking piece when it is safe" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("e1"), square("e2")) in moves
    end

    test "a piece can capture the checking piece" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("e2"), square("e8")) in moves
    end

    test "a sliding check can be blocked" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("d2"), {:white, :bishop})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("d2"), square("e3")) in moves
    end

    test "a pinned rook cannot move off the pin line" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e2"), square("d2")) in moves
      refute Move.new(square("e2"), square("f2")) in moves

      assert Move.new(square("e2"), square("e3")) in moves
      assert Move.new(square("e2"), square("e4")) in moves
    end

    test "a pinned bishop cannot move off the pin line" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("f2"), {:white, :bishop})
        |> Position.put_piece(square("h4"), {:black, :bishop})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("f2"), square("h2")) in moves
      refute Move.new(square("f2"), square("g1")) in moves

      assert Move.new(square("f2"), square("g3")) in moves
      assert Move.new(square("f2"), square("h4")) in moves
    end

    test "in double check only king moves are legal" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("h4"), {:black, :bishop})
        |> Position.put_piece(square("a8"), {:black, :king})
        |> Position.put_piece(square("a1"), {:white, :rook})

      assert Position.in_check?(position, :white)

      moves = Position.legal_moves(position)

      assert moves != []
      assert Enum.all?(moves, &(&1.from == square("e1")))
    end

    test "king cannot move onto a square attacked by a rook" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e2")) in moves
    end

    test "king cannot capture a protected piece" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:black, :rook})
        |> Position.put_piece(square("h5"), {:black, :bishop})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e2")) in moves
    end

    test "king cannot capture the opposing king" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e3"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e3")) in moves
    end

    test "kings cannot move next to each other" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e3"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e2")) in moves
    end

    test "a knight check can be resolved by capturing the knight" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d3"), {:black, :knight})
        |> Position.put_piece(square("c2"), {:white, :bishop})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("c2"), square("d3")) in moves
    end

    test "a knight check can be resolved by moving the king" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d3"), {:black, :knight})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("e1"), square("d1")) in moves
      assert Move.new(square("e1"), square("f1")) in moves
    end

    test "a pawn check can be resolved by capturing the pawn" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("d2"), {:black, :pawn})
        |> Position.put_piece(square("c2"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("c2"), square("d2")) in moves
    end

    test "a diagonal check can be blocked" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h4"), {:black, :bishop})
        |> Position.put_piece(square("g2"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      assert Move.new(square("g2"), square("g3")) in moves
    end

    test "a pinned pawn cannot capture if it exposes the king" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e2"), {:white, :pawn})
        |> Position.put_piece(square("d3"), {:black, :knight})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e2"), square("d3")) in moves
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

      moves = Position.legal_moves(position)

      refute Move.new(square("e5"), square("d6")) in moves
    end

    test "king cannot move next to the opposing king" do
      position =
        Position.new()
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e3"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("e2")) in moves
    end
  end

  describe "castling" do
    test "cannot castle out of check" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("e8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("g1")) in moves
    end

    test "cannot castle through an attacked square" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("f8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("g1")) in moves
    end

    test "cannot castle into check" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("g8"), {:black, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      moves = Position.legal_moves(position)

      refute Move.new(square("e1"), square("g1")) in moves
    end

    test "castling moves both king and rook" do
      position =
        Position.new(castling_rights: MapSet.new([:white_kingside]))
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e1"), square("g1"))
        )

      assert Position.piece_at(position, square("g1")) == {:white, :king}
      assert Position.piece_at(position, square("f1")) == {:white, :rook}
      assert Position.piece_at(position, square("e1")) == nil
      assert Position.piece_at(position, square("h1")) == nil
    end

    test "castling removes the corresponding castling right" do
      position =
        Position.new(
          castling_rights:
            MapSet.new([
              :white_kingside,
              :white_queenside
            ])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e1"), square("g1"))
        )

      refute MapSet.member?(position.castling_rights, :white_kingside)
      refute MapSet.member?(position.castling_rights, :white_queenside)
    end

    test "moving the king removes both castling rights" do
      position =
        Position.new(
          castling_rights:
            MapSet.new([
              :white_kingside,
              :white_queenside
            ])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e1"), square("f1"))
        )

      refute MapSet.member?(position.castling_rights, :white_kingside)
      refute MapSet.member?(position.castling_rights, :white_queenside)
    end

    test "moving a rook removes its castling right" do
      position =
        Position.new(
          castling_rights:
            MapSet.new([
              :white_kingside,
              :white_queenside
            ])
        )
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("h1"), {:white, :rook})
        |> Position.put_piece(square("a1"), {:white, :rook})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("h1"), square("h2"))
        )

      refute MapSet.member?(position.castling_rights, :white_kingside)
      assert MapSet.member?(position.castling_rights, :white_queenside)
    end

    test "capturing a rook removes its castling right" do
      position =
        Position.new(
          side_to_move: :white,
          castling_rights: MapSet.new([:black_kingside, :black_queenside])
        )
        |> Position.put_piece(square("a1"), {:white, :king})
        |> Position.put_piece(square("g7"), {:white, :bishop})
        |> Position.put_piece(square("e8"), {:black, :king})
        |> Position.put_piece(square("h8"), {:black, :rook})

      assert {:ok, position} =
               Position.apply_move(
                 position,
                 Move.new(square("g7"), square("h8"))
               )

      refute MapSet.member?(position.castling_rights, :black_kingside)
      assert MapSet.member?(position.castling_rights, :black_queenside)
    end
  end

  describe "en passant state" do
    test "a non-pawn move clears the en passant target" do
      position = Position.starting_position()

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e2"), square("e4"))
        )

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("g8"), square("f6"))
        )

      assert position.en_passant == nil
    end

    test "an en passant capture removes the captured pawn" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e5"), square("d6"))
        )

      assert Position.piece_at(position, square("d6")) == {:white, :pawn}
      assert Position.piece_at(position, square("d5")) == nil
    end

    test "an en passant capture clears the en passant target" do
      position =
        Position.new(
          side_to_move: :white,
          en_passant: square("d6")
        )
        |> Position.put_piece(square("e5"), {:white, :pawn})
        |> Position.put_piece(square("d5"), {:black, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("e8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e5"), square("d6"))
        )

      assert position.en_passant == nil
    end
  end

  describe "promotion" do
    test "promotion move changes the pawn into the selected piece" do
      position =
        Position.new()
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e7"), square("e8"), :knight)
        )

      assert Position.piece_at(position, square("e8")) == {:white, :knight}
      assert Position.piece_at(position, square("e7")) == nil
    end

    test "a promotion capture changes the pawn into the selected piece" do
      position =
        Position.new()
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("d8"), {:black, :rook})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :king})

      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square("e7"), square("d8"), :bishop)
        )

      assert Position.piece_at(position, square("d8")) == {:white, :bishop}
      assert Position.piece_at(position, square("e7")) == nil
    end

    test "a promotion move cannot use an invalid promotion piece" do
      position =
        Position.new()
        |> Position.put_piece(square("e7"), {:white, :pawn})
        |> Position.put_piece(square("e1"), {:white, :king})
        |> Position.put_piece(square("a8"), {:black, :king})

      assert {:error, :illegal_move} =
               Position.apply_move(
                 position,
                 Move.new(square("e7"), square("e8"), :king)
               )
    end
  end

  describe "checkmate?/2" do
    test "returns true for checkmate" do
      position =
        Position.starting_position()
        |> then(fn position ->
          {:ok, position} =
            Position.apply_move(position, Move.new(square("f2"), square("f3")))

          {:ok, position} =
            Position.apply_move(position, Move.new(square("e7"), square("e5")))

          {:ok, position} =
            Position.apply_move(position, Move.new(square("g2"), square("g4")))

          {:ok, position} =
            Position.apply_move(position, Move.new(square("d8"), square("h4")))

          position
        end)

      assert Position.checkmate?(position, :white)
      refute Position.stalemate?(position, :white)
    end
  end

  describe "stalemate?/2" do
    test "returns true for stalemate" do
      position =
        Position.new(side_to_move: :white)
        |> Position.put_piece(square("h1"), {:white, :king})
        |> Position.put_piece(square("f2"), {:black, :king})
        |> Position.put_piece(square("g3"), {:black, :queen})

      assert Position.stalemate?(position, :white)
      refute Position.checkmate?(position, :white)
    end
  end
end
