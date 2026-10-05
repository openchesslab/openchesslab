defmodule Chess.Notation.SANParseTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.SAN
  alias Chess.Position
  alias Chess.Square

  test "parses pawn and piece moves" do
    position =
      Position.starting_position()

    assert SAN.parse(
             position,
             "e4"
           ) ==
             {:ok,
              move(
                "e2",
                "e4"
              )}

    assert SAN.parse(
             position,
             "Nf3"
           ) ==
             {:ok,
              move(
                "g1",
                "f3"
              )}
  end

  test "rejects a move that is not legal in the position" do
    assert SAN.parse(
             Position.starting_position(),
             "e5"
           ) ==
             {:error, :invalid_san}
  end

  test "parses piece and pawn captures" do
    piece_capture_position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("f3"),
        {:white, :knight}
      )
      |> Position.put_piece(
        square("e5"),
        {:black, :pawn}
      )

    assert SAN.parse(
             piece_capture_position,
             "Nxe5"
           ) ==
             {:ok,
              move(
                "f3",
                "e5"
              )}

    pawn_capture_position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("e4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("d5"),
        {:black, :pawn}
      )

    assert SAN.parse(
             pawn_capture_position,
             "exd5"
           ) ==
             {:ok,
              move(
                "e4",
                "d5"
              )}
  end

  test "parses kingside and queenside castling" do
    kingside =
      [castling_rights: MapSet.new([:white_kingside])]
      |> Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("h1"),
        {:white, :rook}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )

    assert SAN.parse(
             kingside,
             "O-O"
           ) ==
             {:ok,
              move(
                "e1",
                "g1"
              )}

    queenside =
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
        square("e8"),
        {:black, :king}
      )

    assert SAN.parse(
             queenside,
             "O-O-O"
           ) ==
             {:ok,
              move(
                "e1",
                "c1"
              )}

    assert SAN.parse(
             kingside,
             "0-0"
           ) ==
             {:error, :invalid_san}
  end

  test "parses en passant capture" do
    position =
      [side_to_move: :white, en_passant: square("d6")]
      |> Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("e5"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("d5"),
        {:black, :pawn}
      )

    assert SAN.parse(
             position,
             "exd6"
           ) ==
             {:ok,
              move(
                "e5",
                "d6"
              )}
  end

  test "parses promotions including underpromotion" do
    position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("h8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("e7"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        square("d8"),
        {:black, :rook}
      )

    assert SAN.parse(
             position,
             "exd8=N"
           ) ==
             {:ok,
              Move.new(
                square("e7"),
                square("d8"),
                :knight
              )}
  end

  test "requires file disambiguation when multiple pieces can move to the destination" do
    position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("b1"),
        {:white, :knight}
      )
      |> Position.put_piece(
        square("f1"),
        {:white, :knight}
      )

    assert SAN.parse(
             position,
             "Nbd2"
           ) ==
             {:ok,
              move(
                "b1",
                "d2"
              )}

    assert SAN.parse(
             position,
             "Nfd2"
           ) ==
             {:ok,
              move(
                "f1",
                "d2"
              )}

    assert SAN.parse(
             position,
             "Nd2"
           ) ==
             {:error, :invalid_san}
  end

  test "requires rank disambiguation when pieces share a file" do
    position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("a1"),
        {:white, :rook}
      )
      |> Position.put_piece(
        square("a3"),
        {:white, :rook}
      )

    assert SAN.parse(
             position,
             "R1a2"
           ) ==
             {:ok,
              move(
                "a1",
                "a2"
              )}

    assert SAN.parse(
             position,
             "R3a2"
           ) ==
             {:ok,
              move(
                "a3",
                "a2"
              )}

    assert SAN.parse(
             position,
             "Ra2"
           ) ==
             {:error, :invalid_san}
  end

  test "requires complete disambiguation when file and rank are both needed" do
    position =
      Position.new()
      |> Position.put_piece(
        square("e1"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("e8"),
        {:black, :king}
      )
      |> Position.put_piece(
        square("b1"),
        {:white, :knight}
      )
      |> Position.put_piece(
        square("b3"),
        {:white, :knight}
      )
      |> Position.put_piece(
        square("f1"),
        {:white, :knight}
      )

    assert SAN.parse(
             position,
             "Nb1d2"
           ) ==
             {:ok,
              move(
                "b1",
                "d2"
              )}

    assert SAN.parse(
             position,
             "Nbd2"
           ) ==
             {:error, :invalid_san}
  end

  test "requires the canonical check suffix" do
    position =
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
             position,
             "Rh8+"
           ) ==
             {:ok,
              move(
                "h1",
                "h8"
              )}

    assert SAN.parse(
             position,
             "Rh8"
           ) ==
             {:error, :invalid_san}
  end

  test "parses checkmate notation" do
    position =
      Position.new()
      |> Position.put_piece(
        square("f6"),
        {:white, :king}
      )
      |> Position.put_piece(
        square("g6"),
        {:white, :queen}
      )
      |> Position.put_piece(
        square("h8"),
        {:black, :king}
      )

    assert SAN.parse(
             position,
             "Qg7#"
           ) ==
             {:ok,
              move(
                "g6",
                "g7"
              )}

    assert SAN.parse(
             position,
             "Qg7+"
           ) ==
             {:error, :invalid_san}
  end

  test "rejects annotation glyphs because they are PGN rather than SAN" do
    position =
      Position.starting_position()

    assert SAN.parse(
             position,
             "e4!"
           ) ==
             {:error, :invalid_san}
  end

  defp move(from, to) do
    Move.new(
      square(from),
      square(to)
    )
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
