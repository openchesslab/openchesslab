defmodule Features.Chess.MovegenTest do
  use ExUnit.Case, async: true

  alias Features.Chess.{Board, FEN, Move, Movegen}

  @perft_cases [
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 1, 20, []},
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 2, 400, []},
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 3, 8902, []},
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 4, 197_281, []},
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 5, 4_865_609,
     [slow: true]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 1, 48,
     []},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 2, 2039,
     []},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3,
     97_862, []},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 4,
     4_085_603, [slow: true]},
    {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 1, 14, []},
    {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 2, 191, []},
    {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 3, 2812, []},
    {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43_238, []},
    {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 5, 674_624, []},
    {"position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 1, 6, []},
    {"position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 2, 264, []},
    {"position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9467,
     []},
    {"position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 4, 422_333,
     [slow: true]},
    {"position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 1, 44, []},
    {"position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 2, 1486, []},
    {"position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62_379, []},
    {"position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 4, 2_103_487,
     [slow: true]},
    {"position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 1,
     46, []},
    {"position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 2,
     2079, []},
    {"position6", "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 3,
     89_890, []}
  ]

  for {label, fen, depth, expected, tags} <- @perft_cases do
    @tag tags
    test "perft #{label} depth #{depth} == #{expected}" do
      board = FEN.parse(unquote(fen))
      assert Movegen.perft(board, unquote(depth)) == unquote(expected)
    end
  end

  test "startpos legal moves" do
    moves = Board.startpos() |> Movegen.legal_moves() |> uci()

    assert length(moves) == 20

    assert moves -- ~w(a2a3 a2a4 b2b3 b2b4 c2c3 c2c4 d2d3 d2d4 e2e3 e2e4 f2f3 f2f4 g2g3 g2g4
                       h2h3 h2h4 b1a3 b1c3 g1f3 g1h3) == []
  end

  test "kiwipete legal moves include both castles and captures" do
    board = FEN.parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    moves = board |> Movegen.legal_moves() |> uci()

    assert length(moves) == 48
    assert "e1g1" in moves
    assert "e1c1" in moves
    assert "d5e6" in moves
    assert "g2h3" in moves
    assert "f3h3" in moves
  end

  test "castling is unavailable through an attacked square" do
    board = FEN.parse("4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    moves = board |> Movegen.legal_moves() |> uci()

    refute "e1g1" in moves
    assert "e1c1" in moves
  end

  test "castling is unavailable while the king is in check" do
    board = FEN.parse("4k3/8/8/8/8/8/8/r3K2R w K - 0 1")
    moves = board |> Movegen.legal_moves() |> uci()

    refute "e1g1" in moves
    refute "e1c1" in moves
  end

  test "castling through an occupied square is unavailable" do
    board = FEN.parse("r3k2r/8/8/8/8/8/8/RN2K2R w KQ - 0 1")
    moves = board |> Movegen.legal_moves() |> uci()

    refute "e1c1" in moves
    assert "e1g1" in moves
  end

  test "en passant capture is generated and applied" do
    board = FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    moves = board |> Movegen.legal_moves() |> uci()

    assert "e5d6" in moves

    next = Board.apply_move(board, Move.new(36, 43))
    assert Board.piece_at(next, 43) == {:white, :pawns}
    assert Board.piece_at(next, 35) == nil
  end

  test "promotions generate four moves and no plain move" do
    board = FEN.parse("8/P7/8/8/8/8/8/K6k w - - 0 1")

    moves =
      board
      |> Movegen.legal_moves()
      |> Enum.filter(&(&1.from == 48))
      |> Enum.map(&Move.to_uci/1)
      |> Enum.sort()

    assert moves == ~w(a7a8b a7a8n a7a8q a7a8r)
  end

  test "black promotions generate four moves and no plain move" do
    board = FEN.parse("8/8/8/8/8/8/p7/7K b - - 0 1")

    moves =
      board
      |> Movegen.legal_moves()
      |> Enum.filter(&(&1.from == 8))
      |> Enum.map(&Move.to_uci/1)
      |> Enum.sort()

    assert moves == ~w(a2a1b a2a1n a2a1q a2a1r)
  end

  test "a pinned rook may only move along its pin line" do
    board = FEN.parse("4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1")

    moves =
      board
      |> Movegen.legal_moves()
      |> Enum.filter(&(&1.from == 12))
      |> Enum.map(&Move.to_uci/1)
      |> Enum.sort()

    assert moves == ~w(e2e3 e2e4 e2e5 e2e6 e2e7 e2e8)
  end

  test "checkmate leaves no legal moves" do
    board = FEN.parse("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 0 3")

    assert Board.in_check?(board, :white)
    assert Movegen.legal_moves(board) == []
  end

  test "stalemate leaves no legal moves and no check" do
    board = FEN.parse("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")

    refute Board.in_check?(board, :black)
    assert Movegen.legal_moves(board) == []
  end

  test "pseudo legal moves are a superset of legal moves" do
    for fen <- [
          "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
          "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
          "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
        ] do
      board = FEN.parse(fen)
      legal = MapSet.new(Movegen.legal_moves(board), &Move.to_uci/1)
      pseudo = MapSet.new(Movegen.pseudo_legal_moves(board), &Move.to_uci/1)

      assert MapSet.subset?(legal, pseudo)
      assert MapSet.size(legal) <= MapSet.size(pseudo)
    end
  end

  defp uci(moves), do: Enum.map(moves, &Move.to_uci/1)
end
