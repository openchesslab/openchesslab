#!/usr/bin/env python3
"""Oracle values per FEN via python-chess (fase 2 review).

Reads lines "<id>\t<fen>" from /tmp/opencode/oracle-fens.txt and writes one
JSON object per line to /tmp/opencode/oracle-out.jsonl.
"""

import json
import sys

import chess

IN_PATH = "/tmp/opencode/oracle-fens.txt"
OUT_PATH = "/tmp/opencode/oracle-out.jsonl"


def pinned(board, color):
    """Squares of `color`'s pieces that are absolutely pinned to their king."""
    squares = []
    for square, piece in board.piece_map().items():
        if piece.color == color and piece.piece_type != chess.KING:
            if board.is_pinned(color, square):
                squares.append(chess.square_name(square))
    return sorted(squares)


def checks_available(board, color):
    """Number of moves by `color` that give check."""
    probe = board.copy(stack=False)
    probe.turn = color
    return sum(1 for move in probe.legal_moves if probe.gives_check(move))


def pseudo_legal_count(board, color):
    probe = board.copy(stack=False)
    probe.turn = color
    # python-chess pseudo-legal staat koningsslag toe; de catalogus telt die
    # niet mee. Voor de vergelijking uitsluiten.
    return sum(
        1
        for move in probe.pseudo_legal_moves
        if not (
            probe.piece_at(move.to_square) is not None
            and probe.piece_at(move.to_square).piece_type == chess.KING
        )
    )


def attacked_pieces(board, color):
    """Squares of `color`'s pieces attacked by the opponent."""
    enemy = not color
    squares = []
    for square, piece in board.piece_map().items():
        if piece.color == color and board.is_attacked_by(enemy, square):
            squares.append(chess.square_name(square))
    return sorted(squares)


def defended_pieces(board, color):
    """Squares of `color`'s pieces defended by `color` itself."""
    squares = []
    for square, piece in board.piece_map().items():
        if piece.color == color and board.is_attacked_by(color, square):
            squares.append(chess.square_name(square))
    return sorted(squares)


def main():
    out = open(OUT_PATH, "w")
    count = 0

    for line in open(IN_PATH):
        line = line.strip()
        if not line:
            continue

        position_id, fen = line.split("\t", 1)
        board = chess.Board(fen)

        record = {
            "id": int(position_id),
            "stm": "w" if board.turn == chess.WHITE else "b",
            "stm_in_check": board.is_check(),
            "legal_moves_stm": len(list(board.legal_moves)),
            "pseudo_white": pseudo_legal_count(board, chess.WHITE),
            "pseudo_black": pseudo_legal_count(board, chess.BLACK),
            "checks_white": checks_available(board, chess.WHITE),
            "checks_black": checks_available(board, chess.BLACK),
            "absolute_pin_white": pinned(board, chess.WHITE),
            "absolute_pin_black": pinned(board, chess.BLACK),
            "attacked_white": attacked_pieces(board, chess.WHITE),
            "attacked_black": attacked_pieces(board, chess.BLACK),
            "defended_white": defended_pieces(board, chess.WHITE),
            "defended_black": defended_pieces(board, chess.BLACK),
        }

        out.write(json.dumps(record) + "\n")
        count += 1

    out.close()
    print(f"geschreven: {count} records naar {OUT_PATH}")


if __name__ == "__main__":
    sys.exit(main())
