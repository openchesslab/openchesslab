defmodule Chess.Bitboard do
  @moduledoc """
  Represents a chess board using one 64-bit bitboard per piece type and color.
  """

  import Bitwise

  @type piece_type :: Chess.Board.piece_type()
  @type color :: Chess.Board.color()
  @type piece :: Chess.Board.piece()

  @type pseudo_move :: {Chess.Square.t(), non_neg_integer()}

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
    |> pieces()
    |> Enum.filter(fn {_square, {piece_color, _piece_type}} ->
      piece_color == color
    end)
    |> Enum.map(fn {square, {_piece_color, piece_type}} ->
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
  end

  @spec attacked?(t(), color(), Chess.Square.t()) :: boolean()
  def attacked?(board, color, square)
      when color in [:white, :black] and square in 0..63 do
    Enum.any?(pieces(board), fn {from, {piece_color, piece_type}} ->
      piece_color == color and
        attack_bitboard(board, from, piece_type, color)
        |> then(&((&1 &&& 1 <<< square) != 0))
    end)
  end

  @spec rook_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def rook_attacks(board, square) when square in 0..63 do
    board
    |> ray_attacks(square, 8)
    |> bor(ray_attacks(board, square, -8))
    |> bor(ray_attacks(board, square, 1))
    |> bor(ray_attacks(board, square, -1))
  end

  @spec bishop_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def bishop_attacks(board, square) when square in 0..63 do
    ray_attacks(board, square, 9) |||
      ray_attacks(board, square, 7) |||
      ray_attacks(board, square, -7) |||
      ray_attacks(board, square, -9)
  end

  @spec queen_attacks(t(), Chess.Square.t()) :: non_neg_integer()
  def queen_attacks(board, square) when square in 0..63 do
    rook_attacks(board, square) ||| bishop_attacks(board, square)
  end

  @spec king_attacks(Chess.Square.t()) :: non_neg_integer()
  def king_attacks(square) when square in 0..63 do
    file = rem(square, 8)
    rank = div(square, 8)

    for file_offset <- -1..1,
        rank_offset <- -1..1,
        file_offset != 0 or rank_offset != 0,
        target_file = file + file_offset,
        target_rank = rank + rank_offset,
        target_file in 0..7,
        target_rank in 0..7,
        reduce: 0 do
      attacks ->
        target = target_rank * 8 + target_file
        attacks ||| 1 <<< target
    end
  end

  @spec knight_attacks(Chess.Square.t()) :: non_neg_integer()
  def knight_attacks(square) when square in 0..63 do
    file = rem(square, 8)
    rank = div(square, 8)

    offsets = [
      {-2, -1},
      {-2, 1},
      {-1, -2},
      {-1, 2},
      {1, -2},
      {1, 2},
      {2, -1},
      {2, 1}
    ]

    Enum.reduce(offsets, 0, fn {file_offset, rank_offset}, attacks ->
      target_file = file + file_offset
      target_rank = rank + rank_offset

      if target_file in 0..7 and target_rank in 0..7 do
        target = target_rank * 8 + target_file
        attacks ||| 1 <<< target
      else
        attacks
      end
    end)
  end

  @spec pawn_attacks(color(), Chess.Square.t()) :: non_neg_integer()
  def pawn_attacks(:white, square) when square in 0..63 do
    pawn_attacks_for_direction(square, 1)
  end

  def pawn_attacks(:black, square) when square in 0..63 do
    pawn_attacks_for_direction(square, -1)
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

  defp attack_bitboard(_board, square, :pawn, color) do
    pawn_attacks(color, square)
  end

  defp attack_bitboard(_board, square, :knight, _color) do
    knight_attacks(square)
  end

  defp attack_bitboard(_board, square, :king, _color) do
    king_attacks(square)
  end

  defp attack_bitboard(board, square, :bishop, _color) do
    bishop_attacks(board, square)
  end

  defp attack_bitboard(board, square, :rook, _color) do
    rook_attacks(board, square)
  end

  defp attack_bitboard(board, square, :queen, _color) do
    queen_attacks(board, square)
  end

  defp pawn_attacks_for_direction(square, rank_direction) do
    file = rem(square, 8)
    rank = div(square, 8)

    target_rank = rank + rank_direction

    if target_rank in 0..7 do
      attacks =
        if file > 0 do
          1 <<< (target_rank * 8 + file - 1)
        else
          0
        end

      attacks |||
        if file < 7 do
          1 <<< (target_rank * 8 + file + 1)
        else
          0
        end
    else
      0
    end
  end

  defp ray_attacks(board, square, step) do
    ray_attacks(board, square, step, 0)
  end

  defp ray_attacks(board, square, step, attacks) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      attacks = bor(attacks, 1 <<< next)

      if occupied_square?(board, next) do
        attacks
      else
        ray_attacks(board, next, step, attacks)
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
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp occupied_square?(board, square) do
    (occupied(board) &&& 1 <<< square) != 0
  end

  defp popcount(value) do
    popcount(value, 0)
  end

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(value &&& value - 1, count + 1)
  end

  defp put_piece({square, {color, piece_type}}, board) do
    mask = 1 <<< square

    case {color, piece_type} do
      {:white, :pawn} ->
        %{board | white_pawns: bor(board.white_pawns, mask)}

      {:white, :knight} ->
        %{board | white_knights: bor(board.white_knights, mask)}

      {:white, :bishop} ->
        %{board | white_bishops: bor(board.white_bishops, mask)}

      {:white, :rook} ->
        %{board | white_rooks: bor(board.white_rooks, mask)}

      {:white, :queen} ->
        %{board | white_queens: bor(board.white_queens, mask)}

      {:white, :king} ->
        %{board | white_king: bor(board.white_king, mask)}

      {:black, :pawn} ->
        %{board | black_pawns: bor(board.black_pawns, mask)}

      {:black, :knight} ->
        %{board | black_knights: bor(board.black_knights, mask)}

      {:black, :bishop} ->
        %{board | black_bishops: bor(board.black_bishops, mask)}

      {:black, :rook} ->
        %{board | black_rooks: bor(board.black_rooks, mask)}

      {:black, :queen} ->
        %{board | black_queens: bor(board.black_queens, mask)}

      {:black, :king} ->
        %{board | black_king: bor(board.black_king, mask)}
    end
  end

  defp set_piece(board, square, color, type) do
    field = field_for(color, type)
    mask = 1 <<< square

    Map.update!(board, field, &bor(&1, mask))
  end

  defp field_for(:white, :pawn), do: :white_pawns
  defp field_for(:white, :knight), do: :white_knights
  defp field_for(:white, :bishop), do: :white_bishops
  defp field_for(:white, :rook), do: :white_rooks
  defp field_for(:white, :queen), do: :white_queens
  defp field_for(:white, :king), do: :white_king

  defp field_for(:black, :pawn), do: :black_pawns
  defp field_for(:black, :knight), do: :black_knights
  defp field_for(:black, :bishop), do: :black_bishops
  defp field_for(:black, :rook), do: :black_rooks
  defp field_for(:black, :queen), do: :black_queens
  defp field_for(:black, :king), do: :black_king

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
end
