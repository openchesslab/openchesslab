defmodule Features.Chess.ZobristTest do
  use ExUnit.Case, async: true

  alias Features.Chess.{Board, FEN, Zobrist}

  test "startpos hash is stable across runs and deployments" do
    assert Zobrist.hash(Board.startpos()) == 488_707_937_746_885_2380
  end

  test "equal positions hash equally" do
    a = FEN.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    b = FEN.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")

    assert Zobrist.hash(a) == Zobrist.hash(b)
  end

  test "side to move changes the hash" do
    white = FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    black = FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")

    refute Zobrist.hash(white) == Zobrist.hash(black)
  end

  test "castling rights change the hash" do
    full = FEN.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    none = FEN.parse("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")

    refute Zobrist.hash(full) == Zobrist.hash(none)
  end

  test "en passant square changes the hash" do
    with_ep = FEN.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
    without_ep = FEN.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")

    refute Zobrist.hash(with_ep) == Zobrist.hash(without_ep)
  end

  test "piece placement changes the hash" do
    startpos = Board.startpos()
    after_e4 = FEN.parse("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")

    refute Zobrist.hash(startpos) == Zobrist.hash(after_e4)
  end

  test "clocks do not affect the hash" do
    fast = FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    slow = FEN.parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 77 42")

    assert Zobrist.hash(fast) == Zobrist.hash(slow)
  end
end
