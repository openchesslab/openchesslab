defmodule Features.Chess.FENTest do
  use ExUnit.Case, async: true

  alias Features.Chess.{Board, FEN}

  @round_trips [
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
    "8/8/8/8/8/8/8/K6k b - - 7 42"
  ]

  test "start_fen parses to the standard starting position" do
    board = FEN.parse()

    assert FEN.to_fen(board) == FEN.start_fen()
    assert board.side_to_move == :white
    assert board.castling == 0b1111
    assert board.en_passant == nil
    assert board.halfmove_clock == 0
    assert board.fullmove_number == 1
  end

  test "parse and to_fen round-trip" do
    for fen <- @round_trips do
      assert fen |> FEN.parse() |> FEN.to_fen() == fen
    end
  end

  test "missing clocks default to 0 1" do
    board = FEN.parse("8/8/8/8/8/8/8/K6k w - -")

    assert board.halfmove_clock == 0
    assert board.fullmove_number == 1
    assert FEN.to_fen(board) == "8/8/8/8/8/8/8/K6k w - - 0 1"
  end

  test "castling field parsing" do
    assert FEN.parse("8/8/8/8/8/8/8/K6k w - - 0 1").castling == 0
    assert FEN.parse("8/8/8/8/8/8/8/K6k w K - 0 1").castling == 0b0001
    assert FEN.parse("8/8/8/8/8/8/8/K6k w Kq - 0 1").castling == 0b1001
    assert FEN.parse("8/8/8/8/8/8/8/K6k w KQkq - 0 1").castling == 0b1111
  end

  test "en passant field parsing" do
    assert FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1").en_passant == 43
    assert FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1").en_passant == nil
  end

  test "parse raises on invalid FENs" do
    assert_raise ArgumentError, fn -> FEN.parse("8/8/8/8/8/8/8 w - - 0 1") end
    assert_raise ArgumentError, fn -> FEN.parse("8/8/8/8/8/8/8/8 x - - 0 1") end
    assert_raise ArgumentError, fn -> FEN.parse("8/8/8/8/8/8/8/X7 w - - 0 1") end
    assert_raise ArgumentError, fn -> FEN.parse("4k4/8/8/8/8/8/8/8 w - - 0 1") end
    assert_raise ArgumentError, fn -> FEN.parse("only-a-fen") end
  end

  test "board.to_fen delegates to FEN" do
    board = Board.startpos()

    assert Board.to_fen(board) == FEN.to_fen(board)
  end
end
