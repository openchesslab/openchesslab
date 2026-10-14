defmodule Analysis.PositionJsonTest do
  use ExUnit.Case, async: true

  alias Chess.Position

  describe "Jason.Encoder for Chess.Position (delegated via to_wire/1)" do
    test "atoms in the wire form become JSON strings" do
      position =
        Position.new(
          side_to_move: :white,
          castling_rights: MapSet.new([:white_kingside])
        )

      decoded = Jason.decode!(Jason.encode!(position))

      assert decoded["side_to_move"] == "white"
      assert decoded["castling_rights"] == ["white_kingside"]
    end

    test "the encoded JSON parses back to the same to_wire/1 map" do
      position = Position.starting_position()

      decoded = Jason.decode!(Jason.encode!(position))

      assert Enum.sort_by(decoded["pieces"], fn [sq, _] -> sq end) ==
               Enum.sort_by(Position.to_wire(position)["pieces"], fn [sq, _] -> sq end)
    end
  end
end
