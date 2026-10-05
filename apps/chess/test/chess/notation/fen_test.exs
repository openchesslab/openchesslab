defmodule Chess.Notation.FENTest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.FEN
  alias Chess.Position
  alias Chess.Square

  test "parses the standard starting position" do
    assert {:ok, parsed} =
             FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    assert parsed.position ==
             Position.starting_position()

    assert parsed.halfmove_clock ==
             0

    assert parsed.fullmove_number ==
             1
  end

  test "parses a capturable en-passant target" do
    assert {:ok, parsed} =
             FEN.parse("rnbqkbnr/pp2pppp/8/2ppP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3")

    expected =
      Position.starting_position()
      |> apply_move!("e2", "e4")
      |> apply_move!("c7", "c5")
      |> apply_move!("e4", "e5")
      |> apply_move!("d7", "d5")

    assert parsed.position ==
             expected

    assert parsed.position.en_passant ==
             square("d6")

    assert parsed.fullmove_number ==
             3
  end

  test "normalizes a non-capturable FEN en-passant target" do
    assert {:ok, parsed} =
             FEN.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")

    expected =
      Position.starting_position()
      |> apply_move!("e2", "e4")

    assert parsed.position ==
             expected

    assert parsed.position.en_passant ==
             nil
  end

  test "rejects malformed or invalid FEN" do
    assert FEN.parse("8/8/8/8/8/8/8/8 w - - 0 1") ==
             {:error, :invalid_fen}

    assert FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0") ==
             {:error, :invalid_fen}

    assert FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0") ==
             {:error, :invalid_fen}

    assert FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1") ==
             {:error, :invalid_fen}
  end

  defp apply_move!(position, from, to) do
    assert {:ok, position} =
             Position.apply_move(
               position,
               Move.new(
                 square(from),
                 square(to)
               )
             )

    position
  end

  defp square(name) do
    Square.from_algebraic(name)
  end
end
