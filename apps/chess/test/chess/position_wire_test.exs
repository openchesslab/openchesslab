defmodule Chess.PositionWireTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.Square

  describe "to_wire/1 + from_wire/1 round-trip" do
    test "the starting position round-trips" do
      assert {:ok, position} = Position.from_wire(Position.to_wire(Position.starting_position()))
      assert position == Position.starting_position()
    end

    test "an empty board is rejected by validation (and therefore by from_wire)" do
      empty = Position.new(side_to_move: :black)

      assert {:error, _} = Position.from_wire(Position.to_wire(empty))
    end

    test "the wire form omits empty squares" do
      wire = Position.to_wire(Position.new())

      assert wire["pieces"] == []
    end

    test "the wire form places each piece as [square, \"color_kind\"] sorted by square" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e2"), {:white, :pawn})
        |> Position.put_piece(Square.from_algebraic("e7"), {:black, :pawn})
        |> Position.put_piece(Square.from_algebraic("d8"), {:black, :king})

      wire = Position.to_wire(position)

      assert wire["pieces"] == [
               [Square.from_algebraic("e2"), "white_pawn"],
               [Square.from_algebraic("e7"), "black_pawn"],
               [Square.from_algebraic("d8"), "black_king"]
             ]
    end

    test "the wire form preserves castling rights and side" do
      # Narrow castling and flip side so the position stays legal;
      # en_passant validation is stricter (it requires an adjacent
      # enemy pawn to be capturable), so it's covered by its own
      # test below.
      position =
        Position.starting_position()
        |> Map.put(:side_to_move, :black)
        |> Map.update!(:castling_rights, &MapSet.delete(&1, :white_queenside))

      wire = Position.to_wire(position)

      assert wire["side_to_move"] == "black"

      assert Enum.sort(wire["castling_rights"]) == [
               "black_kingside",
               "black_queenside",
               "white_kingside"
             ]

      assert wire["en_passant"] == nil

      assert {:ok, decoded} = Position.from_wire(wire)
      assert decoded == position
    end

    test "a legal en-passant position round-trips" do
      # After 1. e7-e5 black's pawn moved two squares; the en-passant
      # target is e6 (44). For the position to be legal, an adjacent
      # white pawn must be on rank 5.
      position =
        Position.starting_position()
        |> Position.remove_piece(Square.from_algebraic("e7"))
        |> Position.put_piece(Square.from_algebraic("e5"), {:black, :pawn})
        |> Position.remove_piece(Square.from_algebraic("d2"))
        |> Position.put_piece(Square.from_algebraic("d5"), {:white, :pawn})
        |> Map.put(:en_passant, Square.from_algebraic("e6"))

      wire = Position.to_wire(position)

      assert wire["en_passant"] == Square.from_algebraic("e6")

      assert {:ok, decoded} = Position.from_wire(wire)
      assert decoded == position
    end
  end

  describe "Jason.Encoder (delegated via to_wire/1)" do
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

      assert decoded["pieces"]
             |> Enum.sort_by(fn [sq, _] -> sq end) ==
               Position.to_wire(position)["pieces"]
               |> Enum.sort_by(fn [sq, _] -> sq end)
    end
  end
end
