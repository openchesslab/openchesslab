defmodule Chess.PositionPropertiesTest do
  use ExUnit.Case

  alias Chess.Square
  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties

  describe "material/1" do
    test "returns starting position material" do
      material = PositionProperties.material(Position.starting_position())

      assert material.white == %{
               pawn: 8,
               knight: 2,
               bishop: 2,
               rook: 2,
               queen: 1,
               king: 1
             }

      assert material.black == %{
               pawn: 8,
               knight: 2,
               bishop: 2,
               rook: 2,
               queen: 1,
               king: 1
             }
    end

    test "returns zero material for an empty position" do
      material = PositionProperties.material(Position.new())

      assert material.white == %{
               pawn: 0,
               knight: 0,
               bishop: 0,
               rook: 0,
               queen: 0,
               king: 0
             }

      assert material.black == %{
               pawn: 0,
               knight: 0,
               bishop: 0,
               rook: 0,
               queen: 0,
               king: 0
             }
    end

    test "counts pieces correctly" do
      a1_square = Square.from_algebraic("a1")
      b1_square = Square.from_algebraic("b1")
      a2_square = Square.from_algebraic("a2")
      g7_square = Square.from_algebraic("g7")
      g8_square = Square.from_algebraic("g8")

      position =
        Position.new()
        |> Position.put_piece(a1_square, {:white, :king})
        |> Position.put_piece(b1_square, {:white, :queen})
        |> Position.put_piece(a2_square, {:white, :pawn})
        |> Position.put_piece(g7_square, {:black, :king})
        |> Position.put_piece(g8_square, {:black, :rook})

      material = PositionProperties.material(position)

      assert material.white == %{
               pawn: 1,
               knight: 0,
               bishop: 0,
               rook: 0,
               queen: 1,
               king: 1
             }

      assert material.black == %{
               pawn: 0,
               knight: 0,
               bishop: 0,
               rook: 1,
               queen: 0,
               king: 1
             }
    end
  end

  describe "material/1 with a bitboard" do
    test "returns starting position material" do
      position = Position.starting_position()
      bitboard = Chess.Bitboard.from_position(position)

      material = PositionProperties.material(bitboard)

      assert material.white == %{
               pawn: 8,
               knight: 2,
               bishop: 2,
               rook: 2,
               queen: 1,
               king: 1
             }

      assert material.black == %{
               pawn: 8,
               knight: 2,
               bishop: 2,
               rook: 2,
               queen: 1,
               king: 1
             }
    end

    test "returns zero material for an empty bitboard" do
      material = PositionProperties.material(Chess.Bitboard.empty())

      assert material.white == %{
               pawn: 0,
               knight: 0,
               bishop: 0,
               rook: 0,
               queen: 0,
               king: 0
             }

      assert material.black == %{
               pawn: 0,
               knight: 0,
               bishop: 0,
               rook: 0,
               queen: 0,
               king: 0
             }
    end

    test "returns the same material as the position version" do
      position = Position.starting_position()
      bitboard = Chess.Bitboard.from_position(position)

      assert PositionProperties.material(position) ==
               PositionProperties.material(bitboard)
    end
  end

  describe "occupied/1" do
    test "returns occupied squares for starting position" do
      position = Position.starting_position()

      occupied = PositionProperties.occupied(position)

      assert occupied == 0xFFFF00000000FFFF
    end

    test "returns zero for an empty position" do
      assert PositionProperties.occupied(Position.new()) == 0
    end

    test "returns occupied squares from a bitboard" do
      position = Position.starting_position()
      bitboard = Chess.Bitboard.from_position(position)

      assert PositionProperties.occupied(bitboard) ==
               Chess.Bitboard.occupied(bitboard)
    end

    test "position and bitboard versions return the same result" do
      position = Position.starting_position()
      bitboard = Chess.Bitboard.from_position(position)

      assert PositionProperties.occupied(position) ==
               PositionProperties.occupied(bitboard)
    end
  end

  describe "open_files/1" do
    test "starting position has no open files" do
      position = Position.starting_position()

      assert PositionProperties.open_files(position) == []
    end

    test "file without pawns is open" do
      square = Square.from_algebraic("e4")

      position =
        Position.new()
        |> Position.put_piece(square, {:white, :rook})

      assert PositionProperties.open_files(position) ==
               [:a, :b, :c, :d, :e, :f, :g, :h]
    end

    test "white pawn closes a file" do
      square = Square.from_algebraic("e4")

      position =
        Position.new()
        |> Position.put_piece(square, {:white, :pawn})

      refute :e in PositionProperties.open_files(position)
    end

    test "black pawn closes a file" do
      square = Square.from_algebraic("e5")

      position =
        Position.new()
        |> Position.put_piece(square, {:black, :pawn})

      refute :e in PositionProperties.open_files(position)
    end

    test "pieces other than pawns do not close a file" do
      e4_square = Square.from_algebraic("e4")
      e5_square = Square.from_algebraic("e4")

      position =
        Position.new()
        |> Position.put_piece(e4_square, {:white, :rook})
        |> Position.put_piece(e5_square, {:black, :bishop})

      assert :e in PositionProperties.open_files(position)
    end

    test "works directly with a bitboard" do
      d4_square = Square.from_algebraic("d4")
      f5_square = Square.from_algebraic("f5")

      position =
        Position.new()
        |> Position.put_piece(d4_square, {:white, :pawn})
        |> Position.put_piece(f5_square, {:black, :pawn})

      bitboard = Bitboard.from_position(position)

      assert PositionProperties.open_files(bitboard) ==
               [:a, :b, :c, :e, :g, :h]
    end
  end
end
