defmodule Chess.PositionHashTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionHash

  describe "hash/1" do
    test "returns a 32 byte hash" do
      position = Position.starting_position()

      hash = PositionHash.hash(position)

      assert byte_size(hash) == 32
    end

    test "same position produces the same hash" do
      position = Position.starting_position()

      assert PositionHash.hash(position) ==
               PositionHash.hash(position)
    end

    test "different positions produce different hashes" do
      white =
        Position.new(side_to_move: :white)

      black =
        Position.new(side_to_move: :black)

      refute PositionHash.hash(white) ==
               PositionHash.hash(black)
    end

    test "hash is based on the position encoding" do
      position = Position.starting_position()

      expected = :crypto.hash(:sha256, Chess.PositionCodec.encode(position))

      assert PositionHash.hash(position) == expected
    end
  end
end
