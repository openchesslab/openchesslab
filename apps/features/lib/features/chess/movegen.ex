defmodule Features.Chess.Movegen do
  @moduledoc """
  Legal move generation.

  Pseudo-legal moves are generated from precomputed attack tables and
  filtered by making the move and checking that the mover's king is not
  left in check. `perft/2` validates the generator against canonical
  node counts.
  """

  import Bitwise

  alias Features.Chess.{AttackTables, Bitboard, Board, Move}

  @rank_1 0xFF
  @rank_3 0xFF <<< 16
  @rank_6 0xFF <<< 40
  @rank_8 0xFF <<< 56

  @file_a 0x0101010101010101
  @file_h 0x8080808080808080

  @promotion_types [:queens, :rooks, :bishops, :knights]

  @doc """
  All legal moves for the side to move.
  """
  @spec legal_moves(Board.t()) :: [Move.t()]
  def legal_moves(board) do
    color = board.side_to_move

    board
    |> pseudo_legal_moves()
    |> Enum.filter(fn move -> not Board.in_check?(Board.apply_move(board, move), color) end)
  end

  @doc """
  All pseudo-legal moves for the side to move: moves that do not leave the
  mover's own king in check are included, regardless of legality of the
  resulting position (castling through check is excluded).
  """
  @spec pseudo_legal_moves(Board.t()) :: [Move.t()]
  def pseudo_legal_moves(board) do
    color = board.side_to_move
    enemy = Board.opposite(color)
    own = Board.color_occupancy(board, color)
    enemy_kings = Board.piece_bb(board, enemy, :kings)
    enemy_no_king = Board.color_occupancy(board, enemy) &&& bnot(enemy_kings)
    occupancy = Board.occupancy(board)

    pawn_moves(board, color, enemy_no_king) ++
      piece_moves(
        Board.piece_bb(board, color, :knights),
        own,
        enemy_kings,
        &AttackTables.knight/1
      ) ++
      piece_moves(Board.piece_bb(board, color, :bishops), own, enemy_kings, fn square ->
        AttackTables.bishop_attacks(square, occupancy)
      end) ++
      piece_moves(Board.piece_bb(board, color, :rooks), own, enemy_kings, fn square ->
        AttackTables.rook_attacks(square, occupancy)
      end) ++
      piece_moves(Board.piece_bb(board, color, :queens), own, enemy_kings, fn square ->
        AttackTables.queen_attacks(square, occupancy)
      end) ++
      piece_moves(Board.piece_bb(board, color, :kings), own, enemy_kings, &AttackTables.king/1) ++
      castling_moves(board, color)
  end

  @doc """
  Perft node count for `board` at `depth`. Depth `0` counts the position
  itself; depth `1` counts legal moves.
  """
  @spec perft(Board.t(), non_neg_integer()) :: non_neg_integer()
  def perft(_board, 0), do: 1

  def perft(board, depth) when depth > 0 do
    board
    |> legal_moves()
    |> Enum.reduce(0, fn move, acc ->
      acc + perft(Board.apply_move(board, move), depth - 1)
    end)
  end

  defp piece_moves(bitboard, own, enemy_kings, attacks) do
    bitboard
    |> Bitboard.squares()
    |> Enum.flat_map(fn square ->
      (attacks.(square) &&& bnot(own ||| enemy_kings))
      |> Bitboard.squares()
      |> Enum.map(&Move.new(square, &1))
    end)
  end

  defp pawn_moves(board, :white, enemy_no_king) do
    pawns = Board.piece_bb(board, :white, :pawns)
    empty = bnot(Board.occupancy(board))

    forward = pawns <<< 8 &&& empty
    double = (forward &&& @rank_3) <<< 8 &&& empty
    capture_a = (pawns &&& bnot(@file_a)) <<< 7 &&& enemy_no_king
    capture_h = (pawns &&& bnot(@file_h)) <<< 9 &&& enemy_no_king

    target_moves(forward &&& bnot(@rank_8), &(&1 - 8)) ++
      target_moves(double, &(&1 - 16)) ++
      target_moves(capture_a &&& bnot(@rank_8), &(&1 - 7)) ++
      target_moves(capture_h &&& bnot(@rank_8), &(&1 - 9)) ++
      promotion_moves(forward &&& @rank_8, &(&1 - 8)) ++
      promotion_moves(capture_a &&& @rank_8, &(&1 - 7)) ++
      promotion_moves(capture_h &&& @rank_8, &(&1 - 9)) ++
      en_passant_moves(board, :white, pawns)
  end

  defp pawn_moves(board, :black, enemy_no_king) do
    pawns = Board.piece_bb(board, :black, :pawns)
    empty = bnot(Board.occupancy(board))

    forward = pawns >>> 8 &&& empty
    double = (forward &&& @rank_6) >>> 8 &&& empty
    capture_a = (pawns &&& bnot(@file_a)) >>> 9 &&& enemy_no_king
    capture_h = (pawns &&& bnot(@file_h)) >>> 7 &&& enemy_no_king

    target_moves(forward &&& bnot(@rank_1), &(&1 + 8)) ++
      target_moves(double, &(&1 + 16)) ++
      target_moves(capture_a &&& bnot(@rank_1), &(&1 + 9)) ++
      target_moves(capture_h &&& bnot(@rank_1), &(&1 + 7)) ++
      promotion_moves(forward &&& @rank_1, &(&1 + 8)) ++
      promotion_moves(capture_a &&& @rank_1, &(&1 + 9)) ++
      promotion_moves(capture_h &&& @rank_1, &(&1 + 7)) ++
      en_passant_moves(board, :black, pawns)
  end

  defp en_passant_moves(board, color, pawns) do
    case board.en_passant do
      nil ->
        []

      square ->
        (AttackTables.pawn_attackers(color, square) &&& pawns)
        |> Bitboard.squares()
        |> Enum.map(&Move.new(&1, square))
    end
  end

  defp target_moves(targets, from_fun) do
    targets
    |> Bitboard.squares()
    |> Enum.map(fn to -> Move.new(from_fun.(to), to) end)
  end

  defp promotion_moves(targets, from_fun) do
    for to <- Bitboard.squares(targets),
        promotion <- @promotion_types,
        do: Move.new(from_fun.(to), to, promotion)
  end

  defp castling_moves(board, color) do
    enemy = Board.opposite(color)
    occupancy = Board.occupancy(board)
    king_square = if color == :white, do: 4, else: 60
    kings = Board.piece_bb(board, color, :kings)
    rooks = Board.piece_bb(board, color, :rooks)

    {kingside_empty, kingside_rook, queenside_empty, queenside_rook} =
      case color do
        :white -> {[5, 6], 7, [1, 2, 3], 0}
        :black -> {[61, 62], 63, [57, 58, 59], 56}
      end

    king_present = (kings &&& 1 <<< king_square) != 0

    kingside =
      if Board.can_castle?(board, color, :kingside) and king_present and
           (rooks &&& 1 <<< kingside_rook) != 0 and
           all_empty?(occupancy, kingside_empty) and
           safe_squares?(board, [king_square | kingside_empty], enemy) do
        Move.new(king_square, king_square + 2)
      end

    queenside =
      if Board.can_castle?(board, color, :queenside) and king_present and
           (rooks &&& 1 <<< queenside_rook) != 0 and
           all_empty?(occupancy, queenside_empty) and
           safe_squares?(board, [king_square, king_square - 1, king_square - 2], enemy) do
        Move.new(king_square, king_square - 2)
      end

    [kingside, queenside] |> Enum.reject(&is_nil/1)
  end

  defp all_empty?(occupancy, squares) do
    Enum.all?(squares, fn square -> (occupancy &&& 1 <<< square) == 0 end)
  end

  defp safe_squares?(board, squares, enemy) do
    Enum.all?(squares, fn square -> not Board.attacked?(board, square, enemy) end)
  end
end
