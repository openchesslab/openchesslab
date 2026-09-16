defmodule Chess.MoveTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Square

  describe "new/3" do
    test "creates a normal move" do
      move = Move.new(square("e2"), square("e4"))

      assert move.from == square("e2")
      assert move.to == square("e4")
      assert move.promotion == nil
    end

    test "creates a pawn promotion" do
      move = Move.new(square("e7"), square("e8"), :queen)

      assert move.from == square("e7")
      assert move.to == square("e8")
      assert move.promotion == :queen
    end

    test "different promotion pieces produce different moves" do
      queen_promotion = Move.new(square("e7"), square("e8"), :queen)
      rook_promotion = Move.new(square("e7"), square("e8"), :rook)

      assert queen_promotion != rook_promotion
    end

    test "supports all promotion pieces" do
      assert Move.new(square("e7"), square("e8"), :queen).promotion == :queen
      assert Move.new(square("e7"), square("e8"), :rook).promotion == :rook
      assert Move.new(square("e7"), square("e8"), :bishop).promotion == :bishop
      assert Move.new(square("e7"), square("e8"), :knight).promotion == :knight
    end
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
