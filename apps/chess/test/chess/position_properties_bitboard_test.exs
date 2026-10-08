defmodule Chess.PositionPropertiesBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "search-related features match between position and shared bitboard inputs" do
    for position <- sample_positions() do
      board = Bitboard.from_position(position)

      assert PositionProperties.open_files(board) ==
               PositionProperties.open_files(position)

      assert PositionProperties.semi_open_files(board) ==
               PositionProperties.semi_open_files(position)

      assert PositionProperties.outposts(board) ==
               PositionProperties.outposts(position)

      assert PositionProperties.material(board) ==
               PositionProperties.material(position)
    end
  end

  test "both colors' pawn-defended outposts and semi-open files survive shared board use" do
    position =
      Position.new()
      |> place("d4", {:white, :pawn})
      |> place("e5", {:white, :knight})
      |> place("e6", {:black, :pawn})
      |> place("b5", {:black, :pawn})
      |> place("a4", {:black, :knight})

    board = Bitboard.from_position(position)

    assert PositionProperties.outposts(board).white == [square("e5")]
    assert PositionProperties.outposts(board).black == [square("a4")]
    assert :e in PositionProperties.semi_open_files(board).white
    assert :d in PositionProperties.semi_open_files(board).black
  end

  defp sample_positions do
    [
      Position.new(),
      Position.starting_position(),
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn}),
      Position.new()
      |> place("e5", {:white, :knight})
      |> place("d4", {:white, :pawn})
      |> place("f6", {:black, :pawn}),
      Position.new()
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("d4", {:white, :pawn})
      |> place("e5", {:black, :pawn}),
      Position.new()
      |> place("a1", {:white, :rook})
      |> place("h8", {:black, :queen})
    ]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
