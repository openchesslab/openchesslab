defmodule Chess.Bitboard do
  @moduledoc """
  Represents a chess board using one 64-bit bitboard per piece type and color.
  """

  import Bitwise

  @type piece_type :: Chess.Board.piece_type()
  @type color :: Chess.Board.color()
  @type piece :: Chess.Board.piece()

  @type pseudo_move :: {Chess.Square.t(), non_neg_integer()}

  @king_attacks Chess.Bitboard.AttackTables.king_attacks()
  @knight_attacks Chess.Bitboard.AttackTables.knight_attacks()
  @white_pawn_attacks Chess.Bitboard.AttackTables.pawn_attacks(1)
  @black_pawn_attacks Chess.Bitboard.AttackTables.pawn_attacks(-1)

  @type t :: %__MODULE__{
          white_pawns: non_neg_integer(),
          white_knights: non_neg_integer(),
          white_bishops: non_neg_integer(),
          white_rooks: non_neg_integer(),
          white_queens: non_neg_integer(),
          white_king: non_neg_integer(),
          black_pawns: non_neg_integer(),
          black_knights: non_neg_integer(),
          black_bishops: non_neg_integer(),
          black_rooks: non_neg_integer(),
          black_queens: non_neg_integer(),
          black_king: non_neg_integer()
        }

  defstruct [
    :white_pawns,
    :white_knights,
    :white_bishops,
    :white_rooks,
    :white_queens,
    :white_king,
    :black_pawns,
    :black_knights,
    :black_bishops,
    :black_rooks,
    :black_queens,
    :black_king
  ]

  @spec empty() :: t()
  def empty do
    %__MODULE__{
      white_pawns: 0,
      white_knights: 0,
      white_bishops: 0,
      white_rooks: 0,
      white_queens: 0,
      white_king: 0,
      black_pawns: 0,
      black_knights: 0,
      black_bishops: 0,
      black_rooks: 0,
      black_queens: 0,
      black_king: 0
    }
  end

  @spec from_position(Chess.Position.t()) :: t()
  def from_position(%Chess.Position{board: board}) do
    board
    |> Chess.Board.pieces()
    |> Enum.reduce(empty(), &put_piece/2)
  end

  @spec get(t(), Chess.Square.t()) :: piece() | nil
  def get(board, square) when square in 0..63 do
    mask = 1 <<< square

    Enum.find_value(piece_fields(), fn {color, type, field} ->
      if band(Map.fetch!(board, field), mask) != 0 do
        {color, type}
      end
    end)
  end

  @spec put(t(), Chess.Square.t(), piece()) :: t()
  def put(board, square, {color, type})
      when square in 0..63 do
    board
    |> remove(square)
    |> set_piece(square, color, type)
  end

  @spec remove(t(), Chess.Square.t()) :: t()
  def remove(board, square) when square in 0..63 do
    mask = bnot(1 <<< square)

    Enum.reduce(piece_fields(), board, fn {_color, _type, field}, board ->
      Map.update!(board, field, &band(&1, mask))
    end)
  end

  @spec pieces(t()) :: [{Chess.Square.t(), piece()}]
  def pieces(board) do
    for square <- 0..63,
        piece = get(board, square),
        piece != nil do
      {square, piece}
    end
  end

  @spec white_pieces(t()) :: non_neg_integer()
  def white_pieces(board) do
    board.white_pawns
    |> bor(board.white_knights)
    |> bor(board.white_bishops)
    |> bor(board.white_rooks)
    |> bor(board.white_queens)
    |> bor(board.white_king)
  end

  @spec black_pieces(t()) :: non_neg_integer()
  def black_pieces(board) do
    board.black_pawns
    |> bor(board.black_knights)
    |> bor(board.black_bishops)
    |> bor(board.black_rooks)
    |> bor(board.black_queens)
    |> bor(board.black_king)
  end

  @spec occupied(t()) :: non_neg_integer()
  def occupied(board) do
    board
    |> white_pieces()
    |> bor(black_pieces(board))
  end

  @spec count_pieces(non_neg_integer()) :: non_neg_integer()
  def count_pieces(bitboard) do
    popcount(bitboard)
  end

  @spec swap_colors(t()) :: t()
  def swap_colors(board) do
    %__MODULE__{
      white_pawns: board.black_pawns,
      white_knights: board.black_knights,
      white_bishops: board.black_bishops,
      white_rooks: board.black_rooks,
      white_queens: board.black_queens,
      white_king: board.black_king,
      black_pawns: board.white_pawns,
      black_knights: board.white_knights,
      black_bishops: board.white_bishops,
      black_rooks: board.white_rooks,
      black_queens: board.white_queens,
      black_king: board.white_king
    }
  end

  @spec after_move(t(), Chess.Move.t(), piece()) :: t()
  def after_move(
        board,
        %Chess.Move{from: from, to: to, promotion: promotion},
        {color, :pawn}
      ) do
    piece_type = promotion || :pawn

    board
    |> remove(from)
    |> remove(to)
    |> set_piece(to, color, piece_type)
  end

  def after_move(
        board,
        %Chess.Move{from: from, to: to},
        {color, piece_type}
      ) do
    board
    |> remove(from)
    |> remove(to)
    |> set_piece(to, color, piece_type)
  end

  @spec pseudo_moves(t(), color()) :: [pseudo_move()]
  def pseudo_moves(board, color) when color in [:white, :black] do
    friendly = friendly_pieces(board, color)

    board
    |> color_piece_bitboards(color)
    |> Enum.flat_map(fn {piece_type, bitboard} ->
      bitboard
      |> piece_squares()
      |> Enum.map(fn square ->
        {
          square,
          pseudo_moves_for_piece(
            board,
            square,
            piece_type,
            color,
            friendly
          )
        }
      end)
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp color_piece_bitboards(board, :white) do
    [
      {:pawn, board.white_pawns},
      {:knight, board.white_knights},
      {:bishop, board.white_bishops},
      {:rook, board.white_rooks},
      {:queen, board.white_queens},
      {:king, board.white_king}
    ]
  end

  defp color_piece_bitboards(board, :black) do
    [
      {:pawn, board.black_pawns},
      {:knight, board.black_knights},
      {:bishop, board.black_bishops},
      {:rook, board.black_rooks},
      {:queen, board.black_queens},
      {:king, board.black_king}
    ]
  end

  defp piece_squares(bitboard) do
    piece_squares(bitboard, 0, [])
  end

  defp piece_squares(0, _square, acc), do: Enum.reverse(acc)

  defp piece_squares(bitboard, square, acc) do
    acc =
      if (bitboard &&& 1) != 0 do
        [square | acc]
      else
        acc
      end

    piece_squares(bitboard >>> 1, square + 1, acc)
  end

  @spec attacked?(t(), color(), Chess.Square.t()) :: boolean()
  def attacked?(board, color, square)
      when color in [:white, :black] and square in 0..63 do
    occupied = occupied(board)

    pawn_attackers =
      pawn_attacks(opposite_color(color), square)

    knight_attackers =
      knight_attacks(square)

    king_attackers =
      king_attacks(square)

    rook_attack =
      ray_attacked?(
        board,
        occupied,
        square,
        [8, -8, 1, -1],
        color,
        [:rook, :queen]
      )

    bishop_attack =
      ray_attacked?(
        board,
        occupied,
        square,
        [9, 7, -7, -9],
        color,
        [:bishop, :queen]
      )

    (pawn_attackers &&& color_pawns(board, color)) != 0 or
      (knight_attackers &&& color_knights(board, color)) != 0 or
      (king_attackers &&& color_king(board, color)) != 0 or
      rook_attack or
      bishop_attack
  end

  defp color_pawns(board, :white), do: board.white_pawns
  defp color_pawns(board, :black), do: board.black_pawns

  defp color_knights(board, :white), do: board.white_knights
  defp color_knights(board, :black), do: board.black_knights

  defp color_king(board, :white), do: board.white_king
  defp color_king(board, :black), do: board.black_king

  defp ray_attacked?(board, occupied, square, steps, color, piece_types) do
    Enum.any?(steps, fn step ->
      first_piece_on_ray(board, occupied, square, step, color, piece_types)
    end)
  end

  defp first_piece_on_ray(board, occupied, square, step, color, piece_types) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_types do
          [:rook, :queen] ->
            band(color_rooks(board, color), mask) != 0 or
              band(color_queens(board, color), mask) != 0

          [:bishop, :queen] ->
            band(color_bishops(board, color), mask) != 0 or
              band(color_queens(board, color), mask) != 0
        end
      else
        first_piece_on_ray(
          board,
          occupied,
          next,
          step,
          color,
          piece_types
        )
      end
    else
      false
    end
  end

  defp color_rooks(board, :white), do: board.white_rooks
  defp color_rooks(board, :black), do: board.black_rooks

  defp color_bishops(board, :white), do: board.white_bishops
  defp color_bishops(board, :black), do: board.black_bishops

  defp color_queens(board, :white), do: board.white_queens
  defp color_queens(board, :black), do: board.black_queens

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white

  @spec rook_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def rook_attacks(board, square) when square in 0..63 do
    occupied = occupied(board)

    rook_attacks_from_occupied(occupied, square)
  end

  defp rook_attacks_from_occupied(occupied, square) do
    ray_attacks(occupied, square, 8) |||
      ray_attacks(occupied, square, -8) |||
      ray_attacks(occupied, square, 1) |||
      ray_attacks(occupied, square, -1)
  end

  @spec bishop_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def bishop_attacks(board, square) when square in 0..63 do
    occupied = occupied(board)

    bishop_attacks_from_occupied(occupied, square)
  end

  defp bishop_attacks_from_occupied(occupied, square) do
    ray_attacks(occupied, square, 9) |||
      ray_attacks(occupied, square, 7) |||
      ray_attacks(occupied, square, -7) |||
      ray_attacks(occupied, square, -9)
  end

  @spec queen_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def queen_attacks(board, square) when square in 0..63 do
    occupied = occupied(board)

    rook_attacks_from_occupied(occupied, square) |||
      bishop_attacks_from_occupied(occupied, square)
  end

  @spec king_attacks(Chess.Square.t()) :: non_neg_integer()
  def king_attacks(square) when square in 0..63 do
    elem(@king_attacks, square)
  end

  @spec knight_attacks(Chess.Square.t()) :: non_neg_integer()
  def knight_attacks(square) when square in 0..63 do
    elem(@knight_attacks, square)
  end

  @spec pawn_attacks(color(), Chess.Square.t()) :: non_neg_integer()
  def pawn_attacks(:white, square) when square in 0..63 do
    elem(@white_pawn_attacks, square)
  end

  def pawn_attacks(:black, square) when square in 0..63 do
    elem(@black_pawn_attacks, square)
  end

  defp pseudo_moves_for_piece(
         board,
         square,
         :pawn,
         color,
         friendly
       ) do
    pawn_pseudo_moves(board, square, color, friendly)
  end

  defp pseudo_moves_for_piece(
         _board,
         square,
         :knight,
         _color,
         friendly
       ) do
    knight_attacks(square)
    |> band(bnot(friendly))
  end

  defp pseudo_moves_for_piece(
         board,
         square,
         :bishop,
         _color,
         friendly
       ) do
    bishop_attacks(board, square)
    |> band(bnot(friendly))
  end

  defp pseudo_moves_for_piece(
         board,
         square,
         :rook,
         _color,
         friendly
       ) do
    rook_attacks(board, square)
    |> band(bnot(friendly))
  end

  defp pseudo_moves_for_piece(
         board,
         square,
         :queen,
         _color,
         friendly
       ) do
    queen_attacks(board, square)
    |> band(bnot(friendly))
  end

  defp pseudo_moves_for_piece(
         _board,
         square,
         :king,
         _color,
         friendly
       ) do
    king_attacks(square)
    |> band(bnot(friendly))
  end

  defp pawn_pseudo_moves(board, square, color, friendly) do
    occupied = occupied(board)
    enemy = band(occupied, bnot(friendly))

    direction =
      case color do
        :white -> 8
        :black -> -8
      end

    one_step = square + direction

    push =
      if one_step in 0..63 and
           (occupied &&& 1 <<< one_step) == 0 do
        1 <<< one_step
      else
        0
      end

    double_push =
      if push != 0 and pawn_on_starting_rank?(square, color) do
        two_step = square + 2 * direction

        if two_step in 0..63 and
             (occupied &&& 1 <<< two_step) == 0 do
          1 <<< two_step
        else
          0
        end
      else
        0
      end

    captures =
      pawn_attacks(color, square)
      |> band(enemy)

    push ||| double_push ||| captures
  end

  defp pawn_on_starting_rank?(square, :white), do: square in 8..15
  defp pawn_on_starting_rank?(square, :black), do: square in 48..55

  defp friendly_pieces(board, :white), do: white_pieces(board)
  defp friendly_pieces(board, :black), do: black_pieces(board)

  defp ray_attacks(occupied, square, step) do
    ray_attacks(occupied, square, step, 0)
  end

  defp ray_attacks(occupied, square, step, attacks) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      attacks = bor(attacks, 1 <<< next)

      if (occupied &&& 1 <<< next) != 0 do
        attacks
      else
        ray_attacks(occupied, next, step, attacks)
      end
    else
      attacks
    end
  end

  defp valid_ray_square?(_from, to, step) when step in [8, -8] do
    to in 0..63
  end

  defp valid_ray_square?(from, to, 1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, 9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp put_piece({square, piece}, board) do
    put(board, square, piece)
  end

  defp set_piece(board, square, :white, :pawn) do
    %{board | white_pawns: bor(board.white_pawns, 1 <<< square)}
  end

  defp set_piece(board, square, :white, :knight) do
    %{board | white_knights: bor(board.white_knights, 1 <<< square)}
  end

  defp set_piece(board, square, :white, :bishop) do
    %{board | white_bishops: bor(board.white_bishops, 1 <<< square)}
  end

  defp set_piece(board, square, :white, :rook) do
    %{board | white_rooks: bor(board.white_rooks, 1 <<< square)}
  end

  defp set_piece(board, square, :white, :queen) do
    %{board | white_queens: bor(board.white_queens, 1 <<< square)}
  end

  defp set_piece(board, square, :white, :king) do
    %{board | white_king: bor(board.white_king, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :pawn) do
    %{board | black_pawns: bor(board.black_pawns, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :knight) do
    %{board | black_knights: bor(board.black_knights, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :bishop) do
    %{board | black_bishops: bor(board.black_bishops, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :rook) do
    %{board | black_rooks: bor(board.black_rooks, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :queen) do
    %{board | black_queens: bor(board.black_queens, 1 <<< square)}
  end

  defp set_piece(board, square, :black, :king) do
    %{board | black_king: bor(board.black_king, 1 <<< square)}
  end

  defp piece_fields do
    [
      {:white, :pawn, :white_pawns},
      {:white, :knight, :white_knights},
      {:white, :bishop, :white_bishops},
      {:white, :rook, :white_rooks},
      {:white, :queen, :white_queens},
      {:white, :king, :white_king},
      {:black, :pawn, :black_pawns},
      {:black, :knight, :black_knights},
      {:black, :bishop, :black_bishops},
      {:black, :rook, :black_rooks},
      {:black, :queen, :black_queens},
      {:black, :king, :black_king}
    ]
  end

  defp popcount(0), do: 0

  defp popcount(value) do
    popcount(value, 0)
  end

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(value &&& value - 1, count + 1)
  end
end
