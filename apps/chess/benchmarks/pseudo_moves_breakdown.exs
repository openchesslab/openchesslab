alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule PseudoMovesBenchmarkHelpers do
  import Bitwise

  alias Chess.Move
  alias Chess.Position

  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def middlegame_position do
    Position.starting_position()
    |> apply_moves([
      {"e2", "e4"},
      {"e7", "e5"},
      {"g1", "f3"},
      {"b8", "c6"},
      {"f1", "b5"},
      {"a7", "a6"},
      {"b5", "a4"},
      {"g8", "f6"},
      {"e1", "g1"},
      {"f8", "e7"}
    ])
  end

  def check_position do
    Position.new(side_to_move: :white)
    |> Position.put_piece(square("e1"), {:white, :king})
    |> Position.put_piece(square("a1"), {:white, :rook})
    |> Position.put_piece(square("e2"), {:white, :pawn})
    |> Position.put_piece(square("e8"), {:black, :rook})
    |> Position.put_piece(square("a8"), {:black, :king})
  end

  def apply_moves(position, moves) do
    Enum.reduce(moves, position, fn {from, to}, position ->
      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square(from), square(to))
        )

      position
    end)
  end

  def piece_squares(bitboard) do
    piece_squares(bitboard, 0, [])
  end

  def piece_squares(0, _square, acc), do: Enum.reverse(acc)

  def piece_squares(bitboard, square, acc) do
    acc =
      if (bitboard &&& 1) != 0 do
        [square | acc]
      else
        acc
      end

    piece_squares(bitboard >>> 1, square + 1, acc)
  end

  def white_piece_squares(board, piece_type) do
    bitboard =
      case piece_type do
        :pawn -> board.white_pawns
        :knight -> board.white_knights
        :bishop -> board.white_bishops
        :rook -> board.white_rooks
        :queen -> board.white_queens
        :king -> board.white_king
      end

    piece_squares(bitboard)
  end
end

import Bitwise

starting_position = Position.starting_position()
middlegame_position = PseudoMovesBenchmarkHelpers.middlegame_position()
check_position = PseudoMovesBenchmarkHelpers.check_position()

starting_board = Bitboard.from_position(starting_position)
middlegame_board = Bitboard.from_position(middlegame_position)
check_board = Bitboard.from_position(check_position)

positions = %{
  starting: starting_board,
  middlegame: middlegame_board,
  in_check: check_board
}

piece_types = [:pawn, :knight, :bishop, :rook, :queen, :king]

piece_squares = %{
  starting:
    Map.new(piece_types, fn piece_type ->
      {piece_type, PseudoMovesBenchmarkHelpers.white_piece_squares(starting_board, piece_type)}
    end),
  middlegame:
    Map.new(piece_types, fn piece_type ->
      {piece_type, PseudoMovesBenchmarkHelpers.white_piece_squares(middlegame_board, piece_type)}
    end),
  in_check:
    Map.new(piece_types, fn piece_type ->
      {piece_type, PseudoMovesBenchmarkHelpers.white_piece_squares(check_board, piece_type)}
    end)
}

IO.puts("\nWhite piece counts:")

Enum.each(piece_squares, fn {name, squares} ->
  counts =
    for piece_type <- piece_types,
        squares_for_piece = Map.fetch!(squares, piece_type),
        squares_for_piece != [] do
      "#{piece_type}=#{length(squares_for_piece)}"
    end

  IO.puts("#{name}: #{Enum.join(counts, " ")}")
end)

Benchee.run(
  %{
    # ------------------------------------------------------------
    # Piece-square discovery
    # ------------------------------------------------------------

    "starting: pawn squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_pawns)
    end,
    "middlegame: pawn squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_pawns)
    end,
    "in check: pawn squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_pawns)
    end,
    "starting: knight squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_knights)
    end,
    "middlegame: knight squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_knights)
    end,
    "in check: knight squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_knights)
    end,
    "starting: bishop squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_bishops)
    end,
    "middlegame: bishop squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_bishops)
    end,
    "in check: bishop squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_bishops)
    end,
    "starting: rook squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_rooks)
    end,
    "middlegame: rook squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_rooks)
    end,
    "in check: rook squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_rooks)
    end,
    "starting: queen squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_queens)
    end,
    "middlegame: queen squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_queens)
    end,
    "in check: queen squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_queens)
    end,
    "starting: king squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(starting_board.white_king)
    end,
    "middlegame: king squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(middlegame_board.white_king)
    end,
    "in check: king squares" => fn ->
      PseudoMovesBenchmarkHelpers.piece_squares(check_board.white_king)
    end,

    # All six piece bitboards scanned, equivalent to the discovery
    # phase inside pseudo_moves/2.
    "starting: all piece squares" => fn ->
      Enum.each(piece_types, fn piece_type ->
        PseudoMovesBenchmarkHelpers.white_piece_squares(starting_board, piece_type)
      end)
    end,
    "middlegame: all piece squares" => fn ->
      Enum.each(piece_types, fn piece_type ->
        PseudoMovesBenchmarkHelpers.white_piece_squares(middlegame_board, piece_type)
      end)
    end,
    "in check: all piece squares" => fn ->
      Enum.each(piece_types, fn piece_type ->
        PseudoMovesBenchmarkHelpers.white_piece_squares(check_board, piece_type)
      end)
    end,

    # ------------------------------------------------------------
    # Non-sliding attack primitives
    # Piece squares are deliberately precomputed.
    # ------------------------------------------------------------

    "starting: pawn attacks" => fn ->
      Enum.each(piece_squares.starting.pawn, fn square ->
        Bitboard.pawn_attacks(:white, square)
      end)
    end,
    "middlegame: pawn attacks" => fn ->
      Enum.each(piece_squares.middlegame.pawn, fn square ->
        Bitboard.pawn_attacks(:white, square)
      end)
    end,
    "in check: pawn attacks" => fn ->
      Enum.each(piece_squares.in_check.pawn, fn square ->
        Bitboard.pawn_attacks(:white, square)
      end)
    end,
    "starting: knight attacks" => fn ->
      Enum.each(piece_squares.starting.knight, &Bitboard.knight_attacks/1)
    end,
    "middlegame: knight attacks" => fn ->
      Enum.each(piece_squares.middlegame.knight, &Bitboard.knight_attacks/1)
    end,
    "in check: knight attacks" => fn ->
      Enum.each(piece_squares.in_check.knight, &Bitboard.knight_attacks/1)
    end,
    "starting: king attacks" => fn ->
      Enum.each(piece_squares.starting.king, &Bitboard.king_attacks/1)
    end,
    "middlegame: king attacks" => fn ->
      Enum.each(piece_squares.middlegame.king, &Bitboard.king_attacks/1)
    end,
    "in check: king attacks" => fn ->
      Enum.each(piece_squares.in_check.king, &Bitboard.king_attacks/1)
    end,

    # ------------------------------------------------------------
    # Sliding attack primitives
    # Piece squares are deliberately precomputed.
    # ------------------------------------------------------------

    "starting: bishop attacks" => fn ->
      Enum.each(piece_squares.starting.bishop, fn square ->
        Bitboard.bishop_attacks(starting_board, square)
      end)
    end,
    "middlegame: bishop attacks" => fn ->
      Enum.each(piece_squares.middlegame.bishop, fn square ->
        Bitboard.bishop_attacks(middlegame_board, square)
      end)
    end,
    "in check: bishop attacks" => fn ->
      Enum.each(piece_squares.in_check.bishop, fn square ->
        Bitboard.bishop_attacks(check_board, square)
      end)
    end,
    "starting: rook attacks" => fn ->
      Enum.each(piece_squares.starting.rook, fn square ->
        Bitboard.rook_attacks(starting_board, square)
      end)
    end,
    "middlegame: rook attacks" => fn ->
      Enum.each(piece_squares.middlegame.rook, fn square ->
        Bitboard.rook_attacks(middlegame_board, square)
      end)
    end,
    "in check: rook attacks" => fn ->
      Enum.each(piece_squares.in_check.rook, fn square ->
        Bitboard.rook_attacks(check_board, square)
      end)
    end,
    "starting: queen attacks" => fn ->
      Enum.each(piece_squares.starting.queen, fn square ->
        Bitboard.queen_attacks(starting_board, square)
      end)
    end,
    "middlegame: queen attacks" => fn ->
      Enum.each(piece_squares.middlegame.queen, fn square ->
        Bitboard.queen_attacks(middlegame_board, square)
      end)
    end,
    "in check: queen attacks" => fn ->
      Enum.each(piece_squares.in_check.queen, fn square ->
        Bitboard.queen_attacks(check_board, square)
      end)
    end,

    # ------------------------------------------------------------
    # Complete operation
    # ------------------------------------------------------------

    "starting: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(starting_board, :white)
    end,
    "middlegame: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(middlegame_board, :white)
    end,
    "in check: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(check_board, :white)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
