defmodule Chess.PositionCodecTest do
  use ExUnit.Case

  alias Chess.Square
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
      square = Square.from_algebraic("e3")

      without_en_passant = Position.new()

      with_en_passant =
        Position.new(en_passant: square)

      refute PositionCodec.encode(without_en_passant) ==
               PositionCodec.encode(with_en_passant)
    end

    test "different pieces produce different encoding" do
      square = Square.from_algebraic("e4")

      white_pawn =
        Position.new()
        |> Position.put_piece(square, {:white, :pawn})

      black_pawn =
        Position.new()
        |> Position.put_piece(square, {:black, :pawn})

      refute PositionCodec.encode(white_pawn) ==
               PositionCodec.encode(black_pawn)
    end
  end

  describe "decode/1" do
    test "round trips the starting position" do
      position =
        Position.starting_position()

      assert position
             |> PositionCodec.encode()
             |> PositionCodec.decode() ==
               {:ok, position}
    end

    test "round trips all position state" do
      position =
        Position.starting_position()
        |> Map.put(:side_to_move, :black)
        |> Map.put(
          :castling_rights,
          MapSet.new([
            :white_kingside,
            :black_queenside
          ])
        )
        |> Map.put(
          :en_passant,
          Square.from_algebraic("e3")
        )

      assert position
             |> PositionCodec.encode()
             |> PositionCodec.decode() ==
               {:ok, position}
    end

    test "rejects a record with the wrong size" do
      assert PositionCodec.decode(<<1, 2, 3>>) ==
               {:error, :invalid_record_size}
    end

    test "rejects an unknown piece encoding" do
      encoded =
        Position.new()
        |> PositionCodec.encode()

      <<_first, rest::binary>> =
        encoded

      assert PositionCodec.decode(<<99, rest::binary>>) ==
               {:error, {:invalid_piece, 99}}
    end

    test "rejects an invalid side to move" do
      <<
        board::binary-size(64),
        _side,
        castling,
        en_passant
      >> =
        Position.new()
        |> PositionCodec.encode()

      assert PositionCodec.decode(<<
               board::binary,
               2,
               castling,
               en_passant
             >>) ==
               {:error, {:invalid_side_to_move, 2}}
    end

    test "rejects invalid castling bits" do
      <<
        board::binary-size(64),
        side,
        _castling,
        en_passant
      >> =
        Position.new()
        |> PositionCodec.encode()

      assert PositionCodec.decode(<<
               board::binary,
               side,
               16,
               en_passant
             >>) ==
               {:error, {:invalid_castling_rights, 16}}
    end

    test "rejects an invalid en passant square" do
      <<
        board::binary-size(64),
        side,
        castling,
        _en_passant
      >> =
        Position.new()
        |> PositionCodec.encode()

      assert PositionCodec.decode(<<
               board::binary,
               side,
               castling,
               64
             >>) ==
               {:error, {:invalid_en_passant, 64}}
    end
  end
end
