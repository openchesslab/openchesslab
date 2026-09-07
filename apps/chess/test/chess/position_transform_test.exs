defmodule Chess.PositionTransformTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionTransform
  alias Chess.Square

  describe "swap_colors/1" do
    test "swaps the colors of all pieces" do
      a1_square = Square.from_algebraic("a1")
      e4_square = Square.from_algebraic("e4")
      e8_square = Square.from_algebraic("e8")

      position =
        Position.new()
        |> Position.put_piece(a1_square, {:white, :rook})
        |> Position.put_piece(e4_square, {:white, :pawn})
        |> Position.put_piece(e8_square, {:black, :king})

      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(transformed, a1_square) == {:black, :rook}
      assert Position.piece_at(transformed, e4_square) == {:black, :pawn}
      assert Position.piece_at(transformed, e8_square) == {:white, :king}
    end

    test "swaps side to move" do
      white = Position.new(side_to_move: :white)
      black = Position.new(side_to_move: :black)

      assert PositionTransform.swap_colors(white).side_to_move == :black
      assert PositionTransform.swap_colors(black).side_to_move == :white
    end

    test "swaps castling rights" do
      position =
        Position.new(
          castling_rights:
            MapSet.new([
              :white_kingside,
              :white_queenside,
              :black_kingside
            ])
        )

      transformed = PositionTransform.swap_colors(position)

      assert transformed.castling_rights ==
               MapSet.new([
                 :black_kingside,
                 :black_queenside,
                 :white_kingside
               ])
    end

    test "keeps en passant square unchanged" do
      square = Square.from_algebraic("e3")

      position = Position.new(en_passant: square)

      transformed = PositionTransform.swap_colors(position)

      assert transformed.en_passant == square
    end

    test "does not modify the original position" do
      square = Square.from_algebraic("e4")

      position =
        Position.new()
        |> Position.put_piece(square, {:white, :pawn})

      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(position, square) == {:white, :pawn}
      assert Position.piece_at(transformed, square) == {:black, :pawn}
    end

    test "swapping colors twice returns the original position" do
      position =
        Position.starting_position()

      transformed =
        position
        |> PositionTransform.swap_colors()
        |> PositionTransform.swap_colors()

      assert transformed == position
    end

    test "works with the starting position" do
      a1_square = Square.from_algebraic("a1")
      e1_square = Square.from_algebraic("e1")
      e8_square = Square.from_algebraic("e8")
      h8_square = Square.from_algebraic("h8")

      position = Position.starting_position()
      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(transformed, a1_square) == {:black, :rook}
      assert Position.piece_at(transformed, e1_square) == {:black, :king}
      assert Position.piece_at(transformed, e8_square) == {:white, :king}
      assert Position.piece_at(transformed, h8_square) == {:white, :rook}

      assert transformed.side_to_move == :black

      assert transformed.castling_rights ==
               MapSet.new([
                 :white_kingside,
                 :white_queenside,
                 :black_kingside,
                 :black_queenside
               ])
    end
  end
end
