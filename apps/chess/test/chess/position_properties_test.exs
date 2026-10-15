defmodule Chess.PositionPropertiesTest do
  use ExUnit.Case

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

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
      bitboard = Bitboard.from_position(position)

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
      material = PositionProperties.material(Bitboard.empty())

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
      bitboard = Bitboard.from_position(position)

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
      bitboard = Bitboard.from_position(position)

      assert PositionProperties.occupied(bitboard) ==
               Bitboard.occupied(bitboard)
    end

    test "position and bitboard versions return the same result" do
      position = Position.starting_position()
      bitboard = Bitboard.from_position(position)

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

      position = Position.put_piece(Position.new(), square, {:white, :rook})

      assert PositionProperties.open_files(position) ==
               [:a, :b, :c, :d, :e, :f, :g, :h]
    end

    test "white pawn closes a file" do
      square = Square.from_algebraic("e4")

      position = Position.put_piece(Position.new(), square, {:white, :pawn})

      refute :e in PositionProperties.open_files(position)
    end

    test "black pawn closes a file" do
      square = Square.from_algebraic("e5")

      position = Position.put_piece(Position.new(), square, {:black, :pawn})

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

  describe "semi_open_files/1" do
    test "finds files where only one side has a pawn" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("a2"), {:white, :pawn})
        |> Position.put_piece(Square.from_algebraic("b7"), {:black, :pawn})

      assert PositionProperties.semi_open_files(position) == %{
               white: [:b],
               black: [:a]
             }
    end

    test "the starting position has no semi-open files" do
      assert PositionProperties.semi_open_files(Position.starting_position()) ==
               %{white: [], black: []}
    end
  end

  describe "attacked_squares/1" do
    test "includes pawn attacks from the starting position" do
      attacked = PositionProperties.attacked_squares(Position.starting_position())

      a3 = Square.from_algebraic("a3")
      h3 = Square.from_algebraic("h3")
      a6 = Square.from_algebraic("a6")
      h6 = Square.from_algebraic("h6")

      assert a3 in attacked.white
      assert h3 in attacked.white
      assert a6 in attacked.black
      assert h6 in attacked.black
    end

    test "blocks sliding attacks behind occupied squares" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("a1"), {:white, :rook})
        |> Position.put_piece(Square.from_algebraic("a4"), {:black, :pawn})
        |> Position.put_piece(Square.from_algebraic("a8"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("h8"), {:black, :king})

      attacked = PositionProperties.attacked_squares(position)

      assert Square.from_algebraic("a4") in attacked.white
      refute Square.from_algebraic("a5") in attacked.white
    end

    test "excludes squares occupied by the color's own pieces" do
      attacked = PositionProperties.attacked_squares(Position.starting_position())

      # The frontier is covered...
      assert Square.from_algebraic("d3") in attacked.white
      assert Square.from_algebraic("f3") in attacked.white
      # ...but defended own pieces (d2 by the b1-knight, e2 by king/queen/bishop)
      # are not "attacked".
      refute Square.from_algebraic("d2") in attacked.white
      refute Square.from_algebraic("e2") in attacked.white
      refute Square.from_algebraic("e1") in attacked.white
    end
  end

  describe "defended_squares/1" do
    test "lists own pieces the color itself attacks in the starting position" do
      defended = PositionProperties.defended_squares(Position.starting_position())

      # d2: b1-knight, c1-bishop and the queen; f2: the king; a2: the a1-rook.
      assert Square.from_algebraic("d2") in defended.white
      assert Square.from_algebraic("f2") in defended.white
      assert Square.from_algebraic("a2") in defended.white

      # Empty covered squares and undefended own pieces are not defended:
      # the rooks defend their neighbours but are themselves undefended.
      refute Square.from_algebraic("d3") in defended.white
      refute Square.from_algebraic("a1") in defended.white
      refute Square.from_algebraic("h1") in defended.white
    end

    test "defended and attacked squares never overlap" do
      position = Position.starting_position()
      attacked = PositionProperties.attacked_squares(position)
      defended = PositionProperties.defended_squares(position)

      assert MapSet.disjoint?(MapSet.new(attacked.white), MapSet.new(defended.white))
      assert MapSet.disjoint?(MapSet.new(attacked.black), MapSet.new(defended.black))
    end
  end

  describe "attacked_pieces/1" do
    test "lists pieces the opponent attacks" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d5"), {:white, :knight})
        |> Position.put_piece(Square.from_algebraic("c6"), {:black, :pawn})

      attacked = PositionProperties.attacked_pieces(position)

      assert Square.from_algebraic("d5") in attacked.white
    end
  end

  describe "king_zone/2" do
    test "returns the king ring and the squares the opponent attacks" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("e7"), {:black, :rook})

      zone = PositionProperties.king_zone(position, :white)

      assert Square.from_algebraic("e1") in zone.squares
      assert Square.from_algebraic("e2") in zone.squares
      # The e-file rook attacks e2 (e1's ring) through the empty e-file.
      assert Square.from_algebraic("e2") in zone.attacked
      assert Square.from_algebraic("d1") in zone.squares
    end

    test "returns an empty zone when the king is missing" do
      position = Position.new()

      assert PositionProperties.king_zone(position, :white) ==
               %{squares: [], attacked: []}
    end
  end

  describe "outposts/1" do
    test "finds a knight outpost defended by a pawn" do
      e5 = Square.from_algebraic("e5")
      d4 = Square.from_algebraic("d4")

      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(d4, {:white, :pawn})
        |> Position.put_piece(e5, {:white, :knight})
        |> Position.put_piece(Square.from_algebraic("a7"), {:black, :pawn})

      assert e5 in PositionProperties.outposts(position).white
    end

    test "rejects a square enemy pawns can attack" do
      e5 = Square.from_algebraic("e5")

      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})
        |> Position.put_piece(e5, {:white, :knight})
        |> Position.put_piece(Square.from_algebraic("f6"), {:black, :pawn})

      refute e5 in PositionProperties.outposts(position).white
    end

    test "rejects squares an enemy pawn could reach later (a hole is permanent)" do
      e5 = Square.from_algebraic("e5")

      # The f7 pawn does not attack e5 yet, but it can advance to f6 and
      # drive a piece off e5 — so e5 is no outpost.
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})
        |> Position.put_piece(e5, {:white, :knight})
        |> Position.put_piece(Square.from_algebraic("f7"), {:black, :pawn})

      refute e5 in PositionProperties.outposts(position).white
    end

    test "the outpost is the square: occupation by a piece is not required" do
      e5 = Square.from_algebraic("e5")

      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})

      assert e5 in PositionProperties.outposts(position).white
    end

    test "only the fourth to seventh rank count" do
      e3 = Square.from_algebraic("e3")

      # Defended by the d2 pawn, but the third rank is too shallow.
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d2"), {:white, :pawn})
        |> Position.put_piece(e3, {:white, :knight})

      refute e3 in PositionProperties.outposts(position).white

      # The eighth rank is past the opponent's pawns, not an outpost either.
      e8 = Square.from_algebraic("e8")

      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("a8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d7"), {:white, :pawn})
        |> Position.put_piece(Square.from_algebraic("e8"), {:white, :rook})

      refute e8 in PositionProperties.outposts(position).white
    end

    test "mirrors the definition for black" do
      e4 = Square.from_algebraic("e4")

      # Black's fifth rank, defended by the d5 pawn; the white f2 pawn can
      # still advance to f3 and chase a piece off e4, so no outpost.
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("d5"), {:black, :pawn})
        |> Position.put_piece(e4, {:black, :knight})
        |> Position.put_piece(Square.from_algebraic("f2"), {:white, :pawn})

      refute e4 in PositionProperties.outposts(position).black

      # Without the f2 pawn it is a hole and an outpost.
      position = Position.remove_piece(position, Square.from_algebraic("f2"))

      assert e4 in PositionProperties.outposts(position).black
    end
  end

  describe "space/1" do
    test "measures opponent-half control, split by pawns" do
      space = PositionProperties.space(Position.starting_position())

      # No piece reaches the opponent's half from the start.
      assert space.white == %{controlled: 0, pawn_space: 0}
      assert space.black == %{controlled: 0, pawn_space: 0}
    end

    test "counts controlled squares in the opponent half" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("e5"), {:white, :knight})

      space = PositionProperties.space(position)

      # The e5 knight attacks d7, f7, c6, g6, d3, f3, c4, g4; the four
      # squares on ranks 6-7 are in Black's half.
      assert space.white.controlled == 4
    end
  end

  describe "in_check/1" do
    test "reports the attacked king" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
        |> Position.put_piece(Square.from_algebraic("e4"), {:black, :rook})

      assert PositionProperties.in_check(position) == %{white: true, black: false}
    end

    test "reports neither king when both are safe" do
      position =
        Position.new()
        |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
        |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})

      assert PositionProperties.in_check(position) == %{white: false, black: false}
    end

    test "reports a missing king as not in check" do
      position = Position.put_piece(Position.new(), Square.from_algebraic("e1"), {:white, :king})

      assert PositionProperties.in_check(position) == %{white: false, black: false}
    end
  end
end
