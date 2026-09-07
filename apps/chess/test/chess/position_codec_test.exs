defmodule Chess.PositionCodecTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionCodec

  describe "encode/1" do
    test "always produces the same binary for the same position" do
      position = Position.starting_position()

      assert PositionCodec.encode(position) ==
               PositionCodec.encode(position)
    end

    test "encodes the board using one byte per square" do
      position = Position.new()

      encoded = PositionCodec.encode(position)

      assert byte_size(encoded) == 67
    end

    test "different side to move produces different encoding" do
      white =
        Position.new(side_to_move: :white)

      black =
        Position.new(side_to_move: :black)

      refute PositionCodec.encode(white) ==
               PositionCodec.encode(black)
    end

    test "different castling rights produce different encoding" do
      without_castling = Position.new()

      with_castling =
        Position.new(castling_rights: MapSet.new([:white_kingside]))

      refute PositionCodec.encode(without_castling) ==
               PositionCodec.encode(with_castling)
    end

    test "different en passant squares produce different encoding" do
      without_en_passant = Position.new()

      with_en_passant =
        Position.new(en_passant: 20)

      refute PositionCodec.encode(without_en_passant) ==
               PositionCodec.encode(with_en_passant)
    end

    test "different pieces produce different encoding" do
      white_pawn =
        Position.new()
        |> Position.put_piece(28, {:white, :pawn})

      black_pawn =
        Position.new()
        |> Position.put_piece(28, {:black, :pawn})

      refute PositionCodec.encode(white_pawn) ==
               PositionCodec.encode(black_pawn)
    end
  end
end
