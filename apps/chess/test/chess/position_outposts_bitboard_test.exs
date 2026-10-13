defmodule Chess.PositionOutpostsBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "finds pawn-defended knight outposts of both colors" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{
             white: [square("h5")],
             black: [square("a4")]
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

  test "rejects unsupported knights and knights on their own half" do
    position =
      Position.new()
      |> place("e5", {:white, :knight})
      |> place("h4", {:white, :knight})
      |> place("g3", {:white, :pawn})
      |> place("a5", {:black, :knight})
      |> place("b6", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{white: [], black: []}
  end

  test "returns ordered square lists with no file-edge wraparound" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("e5", {:white, :knight})
      |> place("d4", {:white, :pawn})
      |> place("a6", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{
             white: [square("e5"), square("h5")],
             black: []
           }
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
