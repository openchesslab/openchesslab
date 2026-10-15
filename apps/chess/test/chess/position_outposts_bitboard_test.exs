defmodule Chess.PositionOutpostsBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "finds pawn-defended outposts of both colors, occupied or not" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn})

    # The g4 pawn also covers the empty f5; the b5 pawn also covers c4.
    assert PositionProperties.outposts(position) == %{
             white: [square("f5"), square("h5")],
             black: [square("a4"), square("c4")]
           }
  end

  test "rejects both outposts when enemy pawns attack their squares" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn})
      |> place("g6", {:black, :pawn})
      |> place("b3", {:white, :pawn})

    assert PositionProperties.outposts(position) == %{white: [], black: []}
  end

  test "a knight is neither required nor sufficient: the square is the outpost" do
    position =
      Position.new()
      |> place("e5", {:white, :knight})
      |> place("h4", {:white, :knight})
      |> place("g3", {:white, :pawn})
      |> place("a5", {:black, :knight})
      |> place("b6", {:black, :pawn})

    # e5 is pawn-unsupported, so no outpost despite the knight; the defended
    # squares f4/h4 (white) and a5/c5 (black) are outposts, knights or not.
    assert PositionProperties.outposts(position) == %{
             white: [square("f4"), square("h4")],
             black: [square("a5"), square("c5")]
           }
  end

  test "returns ordered square lists with no file-edge wraparound" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("e5", {:white, :knight})
      |> place("d4", {:white, :pawn})
      |> place("a6", {:black, :pawn})

    # All four pawn-covered fifth-rank squares are holes for black; b5 is a
    # hole for white.
    assert PositionProperties.outposts(position) == %{
             white: [square("c5"), square("e5"), square("f5"), square("h5")],
             black: [square("b5")]
           }
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
