defmodule Analysis.MoveJSONTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Square

  describe "Jason.Encoder for Chess.Move" do
    test "encodes a normal move with promotion: null" do
      move = Move.new(Square.from_algebraic("e2"), Square.from_algebraic("e4"))

      assert Jason.decode!(Jason.encode!(move)) == %{
               "from" => 12,
               "to" => 28,
               "promotion" => nil
             }
    end

    test "encodes a pawn promotion with the atom as a lowercase string" do
      move = Move.new(Square.from_algebraic("e7"), Square.from_algebraic("e8"), :queen)

      assert Jason.decode!(Jason.encode!(move)) == %{
               "from" => 52,
               "to" => 60,
               "promotion" => "queen"
             }
    end

    test "encodes each promotion kind as its own string" do
      for promotion <- [:queen, :rook, :bishop, :knight] do
        move = Move.new(Square.from_algebraic("a7"), Square.from_algebraic("a8"), promotion)

        decoded = Jason.decode!(Jason.encode!(move))
        assert decoded["promotion"] == Atom.to_string(promotion)
      end
    end
  end
end
