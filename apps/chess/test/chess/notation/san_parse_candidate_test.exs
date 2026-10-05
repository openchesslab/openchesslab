defmodule Chess.Notation.SANParseCandidateTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.SAN
  alias Chess.Position
  alias Chess.Square

  test "parses castling with a canonical check suffix" do
    position =
      [castling_rights: MapSet.new([:white_queenside])]
      |> Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("a1"),
        {:white, :rook}
      )
      |> Position.put_piece(
        square("d8"),
        {:black, :king}
      )

    assert SAN.parse(
             position,
             "O-O-O+"
           ) ==
             {:ok,
              Move.new(
                square("e1"),
                square("c1")
              )}
  end

  test "rejects malformed SAN without a destination square" do
    position =
      Position.starting_position()

    assert SAN.parse(
             position,
             "N"
           ) ==
             {:error, :invalid_san}

    assert SAN.parse(
             position,
             "Nx"
           ) ==
             {:error, :invalid_san}
  end

  test "rejects malformed SAN with an invalid destination square" do
    position =
      Position.starting_position()

    assert SAN.parse(
             position,
             "Ne9"
           ) ==
             {:error, :invalid_san}

    assert SAN.parse(
             position,
             "i4"
           ) ==
             {:error, :invalid_san}
  end

  test "still requires canonical check and checkmate suffixes" do
    check_position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("a8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("h1"),
        {:white, :rook}
      )

    assert SAN.parse(
             check_position,
             "Rh8+"
           ) ==
             {:ok,
              Move.new(
                square("h1"),
                square("h8")
              )}

    assert SAN.parse(
             check_position,
             "Rh8"
           ) ==
             {:error, :invalid_san}
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
