defmodule Chess.PositionInCheckBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "a shared bitboard produces the same check statuses as Position.in_check?/2" do
    for position <- sample_positions() do
      expected = %{
        white: Position.in_check?(position, :white),
        black: Position.in_check?(position, :black)
      }

      assert PositionProperties.in_check(position) == expected
      assert PositionProperties.in_check(Bitboard.from_position(position)) == expected
    end
  end

  test "both kings can be in check in an edited position" do
    position =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e4", {:black, :rook})
      |> place("e5", {:white, :rook})

    assert PositionProperties.in_check(position) == %{white: true, black: true}

    assert PositionProperties.in_check(Bitboard.from_position(position)) == %{
             white: true,
             black: true
           }
  end

  test "missing kings are not reported in check" do
    only_white_king = place(Position.new(), "e1", {:white, :king})
    only_black_king = place(Position.new(), "e8", {:black, :king})

    for position <- [Position.new(), only_white_king, only_black_king] do
      assert PositionProperties.in_check(Bitboard.from_position(position)) == %{
               white: false,
               black: false
             }
    end
  end

  test "multiple kings preserve the original lowest-square selection" do
    # The higher white king on h7 is attacked by the black knight on f8,
    # but the white king on e1 is considered first and is safe.
    white =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h7", {:white, :king})
      |> place("f8", {:black, :knight})

    assert PositionProperties.in_check(white).white == false
    assert PositionProperties.in_check(Bitboard.from_position(white)).white == false

    # The black king on e8 is attacked, but the first king on a8 is safe.
    black =
      Position.new()
      |> place("a8", {:black, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})

    assert PositionProperties.in_check(black).black == false
    assert PositionProperties.in_check(Bitboard.from_position(black)).black == false

    # The first white king is attacked, despite a second, safe white king.
    first_checked =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h7", {:white, :king})
      |> place("e4", {:black, :rook})

    assert PositionProperties.in_check(first_checked).white == true
    assert PositionProperties.in_check(Bitboard.from_position(first_checked)).white == true
  end

  defp sample_positions do
    [
      Position.new(),
      Position.starting_position(),
      place(Position.new(), "e1", {:white, :king}),
      place(Position.new(), "e8", {:black, :king}),
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook}),
      Position.new()
      |> place("a1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook}),
      Position.new()
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e4", {:black, :rook})
      |> place("e5", {:white, :rook}),
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h7", {:white, :king})
      |> place("f8", {:black, :knight}),
      Position.new()
      |> place("a8", {:black, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})
    ]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, Square.from_algebraic(algebraic), piece)
  end
end
