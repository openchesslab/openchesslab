defmodule Chess.PositionTest do
  use ExUnit.Case

  alias Chess.Position

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
end
