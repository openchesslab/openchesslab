defmodule Chess.PositionTransformTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionTransform

  describe "swap_colors/1" do
    test "swaps the colors of all pieces" do
      position =
        Position.new()
        |> Position.put_piece(0, {:white, :rook})
        |> Position.put_piece(28, {:white, :pawn})
        |> Position.put_piece(60, {:black, :king})

      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(transformed, 0) == {:black, :rook}
      assert Position.piece_at(transformed, 28) == {:black, :pawn}
      assert Position.piece_at(transformed, 60) == {:white, :king}
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
      position = Position.new(en_passant: 20)

      transformed = PositionTransform.swap_colors(position)

      assert transformed.en_passant == 20
    end

    test "does not modify the original position" do
      position =
        Position.new()
        |> Position.put_piece(28, {:white, :pawn})

      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(position, 28) == {:white, :pawn}
      assert Position.piece_at(transformed, 28) == {:black, :pawn}
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
      position = Position.starting_position()
      transformed = PositionTransform.swap_colors(position)

      assert Position.piece_at(transformed, 0) == {:black, :rook}
      assert Position.piece_at(transformed, 4) == {:black, :king}
      assert Position.piece_at(transformed, 60) == {:white, :king}
      assert Position.piece_at(transformed, 63) == {:white, :rook}

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
