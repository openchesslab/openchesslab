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
  end

  test "checkmate?/2 returns true for checkmate" do
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

  test "stalemate?/2 returns true for stalemate" do
    position =
      Position.new(side_to_move: :white)
      |> Position.put_piece(square("h1"), {:white, :king})
      |> Position.put_piece(square("f2"), {:black, :king})
      |> Position.put_piece(square("g3"), {:black, :queen})

    assert Position.stalemate?(position, :white)
    refute Position.checkmate?(position, :white)
  end
end
