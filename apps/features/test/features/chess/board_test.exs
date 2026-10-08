defmodule Features.Chess.BoardTest do
  use ExUnit.Case, async: true

  alias Features.Chess.{Board, FEN, Move}

  test "piece_at and piece_at!" do
    board = Board.startpos()

    assert Board.piece_at(board, 0) == {:white, :rooks}
    assert Board.piece_at(board, 4) == {:white, :kings}
    assert Board.piece_at(board, 60) == {:black, :kings}
    assert Board.piece_at(board, 27) == nil
    assert Board.piece_at!(board, 4) == {:white, :kings}

    assert_raise ArgumentError, fn -> Board.piece_at!(board, 27) end
  end

  test "double push sets the en passant square, quiet moves clear it" do
    board = Board.startpos()
    after_e4 = Board.apply_move(board, Move.new(12, 28))

    assert after_e4.en_passant == 20

    after_quiet = Board.apply_move(after_e4, Move.new(62, 45))

    assert after_quiet.en_passant == nil
  end

  test "en passant capture removes the captured pawn" do
    board = FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    next = Board.apply_move(board, Move.new(36, 43))

    assert Board.piece_at(next, 43) == {:white, :pawns}
    assert Board.piece_at(next, 35) == nil
    assert next.en_passant == nil
  end

  test "castling moves the rook alongside the king and drops rights" do
    board = FEN.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    next = Board.apply_move(board, Move.new(4, 6))

    assert Board.piece_at(next, 6) == {:white, :kings}
    assert Board.piece_at(next, 5) == {:white, :rooks}
    assert Board.piece_at(next, 4) == nil
    assert Board.piece_at(next, 7) == nil
    assert Board.castling_to_string(next.castling) == "kq"
  end

  test "capturing a rook on its home square clears its castling right" do
    board = FEN.parse("r3k2r/8/8/8/8/8/R7/4K2k w KQkq - 0 1")
    next = Board.apply_move(board, Move.new(8, 56))

    assert Board.piece_at(next, 56) == {:white, :rooks}
    assert Board.castling_to_string(next.castling) == "KQk"
  end

  test "moving the king clears both of its castling rights" do
    board = FEN.parse("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
    next = Board.apply_move(board, Move.new(60, 62))

    assert Board.castling_to_string(next.castling) == "KQ"
  end

  test "promotion replaces the pawn" do
    board = FEN.parse("8/P7/8/8/8/8/8/K6k w - - 0 1")
    next = Board.apply_move(board, Move.new(48, 56, :queens))

    assert Board.piece_at(next, 56) == {:white, :queens}
    assert Board.piece_at(next, 48) == nil
    assert Board.piece_bb(next, :white, :pawns) == 0
  end

  test "side to move flips and fullmove increments after black" do
    board = FEN.parse("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    after_white = Board.apply_move(board, Move.new(4, 6))
    after_black = Board.apply_move(after_white, Move.new(60, 62))

    assert after_white.side_to_move == :black
    assert after_white.fullmove_number == 1
    assert after_black.side_to_move == :white
    assert after_black.fullmove_number == 2
  end

  test "halfmove clock resets on pawn moves and captures" do
    board = FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - d6 9 40")
    after_capture = Board.apply_move(board, Move.new(36, 43))
    after_quiet = Board.apply_move(board, Move.new(4, 5))

    assert after_capture.halfmove_clock == 0
    assert after_quiet.halfmove_clock == 10
  end

  test "in_check?" do
    in_check = FEN.parse("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 0 3")

    assert Board.in_check?(in_check, :white)
    refute Board.in_check?(in_check, :black)
    refute Board.in_check?(Board.startpos(), :white)
    refute Board.in_check?(Board.startpos(), :black)
  end

  test "attacked? sees pawns, knights, kings and sliders" do
    board = FEN.parse("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 1")

    assert Board.attacked?(board, 43, :white)
    refute Board.attacked?(board, 43, :black)

    knights = FEN.parse("4k3/8/8/8/8/8/8/3K1N1r w - - 0 1")
    assert Board.attacked?(knights, 20, :white)
    refute Board.attacked?(knights, 20, :black)
  end
end
