defmodule Features.Chess.Board do
  @moduledoc """
  Immutable bitboard representation of a chess position.

  Piece sets are stored per `{color, type}` as 64-bit integer bitboards
  (square `a1 = 0` .. `h8 = 63`), with cached per-color occupancies.
  Castling rights use the bitfield: white kingside `1`, white queenside
  `2`, black kingside `4`, black queenside `8`.
  """

  import Bitwise

  alias Features.Chess.{AttackTables, Bitboard, Move, Square}

  @types [:pawns, :knights, :bishops, :rooks, :queens, :kings]
  @colors [:white, :black]

  @pieces_list for color <- @colors, type <- @types, do: {color, type}

  @castle_wk 1
  @castle_wq 2
  @castle_bk 4
  @castle_bq 8

  defstruct pieces: %{},
            white: 0,
            black: 0,
            side_to_move: :white,
            castling: 0,
            en_passant: nil,
            halfmove_clock: 0,
            fullmove_number: 1,
            attack_table: nil,
            evaluation_cache: nil,
            similarity_cache: nil

  @type color :: :white | :black
  @type piece_type :: :pawns | :knights | :bishops | :rooks | :queens | :kings
  @type piece :: {color(), piece_type()}
  @type castling :: 0..15
  @type attack_table :: %{color() => {map(), non_neg_integer()}} | nil
  @type evaluation_cache :: map() | nil
  @type similarity_cache :: map() | nil

  @type t :: %__MODULE__{
          pieces: %{piece() => non_neg_integer()},
          white: non_neg_integer(),
          black: non_neg_integer(),
          side_to_move: color(),
          castling: castling(),
          en_passant: 0..63 | nil,
          halfmove_clock: non_neg_integer(),
          fullmove_number: pos_integer(),
          attack_table: attack_table(),
          evaluation_cache: evaluation_cache(),
          similarity_cache: similarity_cache()
        }

  @doc "The standard starting position."
  @spec startpos() :: t
  def startpos, do: Features.Chess.FEN.parse()

  @doc """
  Build a board from a `%{{color, type} => bitboard}` map. Missing piece
  types default to empty; `attrs` overrides the non-piece fields.
  """
  @spec build(map(), keyword()) :: t
  def build(pieces, attrs \\ []) do
    pieces = Map.merge(empty_pieces(), pieces)

    struct(
      %__MODULE__{
        pieces: pieces,
        white: color_bb(pieces, :white),
        black: color_bb(pieces, :black)
      },
      attrs
    )
  end

  @doc "All piece types."
  def types, do: @types

  @doc "All colors."
  def colors, do: @colors

  @doc "Bitboard of `type` pieces belonging to `color`."
  @spec piece_bb(t(), color(), piece_type()) :: non_neg_integer()
  def piece_bb(board, color, type), do: Map.fetch!(board.pieces, {color, type})

  @doc "Occupancy of all pieces on the board."
  @spec occupancy(t()) :: non_neg_integer()
  def occupancy(board), do: board.white ||| board.black

  @doc "Occupancy of all pieces belonging to `color`."
  @spec color_occupancy(t(), color()) :: non_neg_integer()
  def color_occupancy(board, :white), do: board.white
  def color_occupancy(board, :black), do: board.black

  @spec opposite(color()) :: color()
  def opposite(:white), do: :black
  def opposite(:black), do: :white

  @doc "The piece on `square`, as `{color, type}`, or `nil`."
  @spec piece_at(t(), 0..63) :: piece() | nil
  def piece_at(board, square) when square in 0..63 do
    bit = 1 <<< square

    Enum.find_value(@pieces_list, fn key ->
      if (Map.fetch!(board.pieces, key) &&& bit) != 0, do: key
    end)
  end

  @doc "Like `piece_at/2`, but raises when the square is empty."
  @spec piece_at!(t(), 0..63) :: piece()
  def piece_at!(board, square) do
    piece_at(board, square) ||
      raise ArgumentError, "no piece on square #{Square.to_string(square)}"
  end

  @doc "Whether `square` is attacked by any piece of `color`."
  @spec attacked?(t(), 0..63, color()) :: boolean()
  def attacked?(board, square, color) when square in 0..63 do
    (AttackTables.pawn_attackers(color, square) &&& piece_bb(board, color, :pawns)) != 0 or
      (AttackTables.knight(square) &&& piece_bb(board, color, :knights)) != 0 or
      (AttackTables.king(square) &&& piece_bb(board, color, :kings)) != 0 or
      slider_attacked?(board, color, AttackTables.bishop_rays(square), [
        :bishops,
        :queens
      ]) or
      slider_attacked?(board, color, AttackTables.rook_rays(square), [
        :rooks,
        :queens
      ])
  end

  @doc "Whether `color`'s king is in check."
  @spec in_check?(t(), color()) :: boolean()
  def in_check?(board, color) do
    kings = piece_bb(board, color, :kings)
    kings != 0 and attacked?(board, Bitboard.least_square(kings), opposite(color))
  end

  @doc """
  Apply `move` and return the resulting position. Castling moves the rook
  alongside the king, en passant removes the captured pawn, promotions
  replace the pawn with the promotion piece.
  """
  @spec apply_move(t(), Move.t()) :: t
  def apply_move(%__MODULE__{} = board, %Move{from: from, to: to, promotion: promotion}) do
    {color, type} = piece_at!(board, from)
    enemy = opposite(color)

    {captured, captured_square} = capture_target(board, color, type, to)

    pieces =
      board.pieces
      |> remove_piece(color, type, from)
      |> remove_captured(captured, captured_square)
      |> place_piece(color, promotion || type, to)
      |> move_castle_rook(color, type, from, to)

    %{
      board
      | pieces: pieces,
        white: color_bb(pieces, :white),
        black: color_bb(pieces, :black),
        side_to_move: enemy,
        castling: update_castling(board.castling, from, to),
        en_passant: en_passant_square(type, from, to),
        halfmove_clock:
          if(type == :pawns or captured != nil, do: 0, else: board.halfmove_clock + 1),
        fullmove_number:
          if(color == :black, do: board.fullmove_number + 1, else: board.fullmove_number),
        attack_table: nil,
        evaluation_cache: nil,
        similarity_cache: nil
    }
  end

  @doc "Whether `color` may castle toward `side` according to the rights bitfield."
  @spec can_castle?(t(), color(), :kingside | :queenside) :: boolean()
  def can_castle?(board, color, side) do
    (board.castling &&& castle_flag(color, side)) != 0
  end

  @doc "The castling-rights bit for `color` and `side`."
  @spec castle_flag(color(), :kingside | :queenside) :: castling()
  def castle_flag(:white, :kingside), do: @castle_wk
  def castle_flag(:white, :queenside), do: @castle_wq
  def castle_flag(:black, :kingside), do: @castle_bk
  def castle_flag(:black, :queenside), do: @castle_bq

  @doc ~S(Parse a FEN castling field like `"KQkq"` into the rights bitfield.)
  @spec parse_castling(String.t()) :: castling()
  def parse_castling("-"), do: 0

  def parse_castling(letters) do
    Enum.reduce(String.graphemes(letters), 0, fn
      "K", acc -> acc ||| @castle_wk
      "Q", acc -> acc ||| @castle_wq
      "k", acc -> acc ||| @castle_bk
      "q", acc -> acc ||| @castle_bq
      other, _acc -> raise ArgumentError, "invalid castling rights: #{inspect(other)}"
    end)
  end

  @doc ~S(Serialize the rights bitfield as a FEN castling field like `"KQkq"`.)
  @spec castling_to_string(castling()) :: String.t()
  def castling_to_string(0), do: "-"

  def castling_to_string(castling) do
    ""
    |> maybe_flag(castling, @castle_wk, "K")
    |> maybe_flag(castling, @castle_wq, "Q")
    |> maybe_flag(castling, @castle_bk, "k")
    |> maybe_flag(castling, @castle_bq, "q")
  end

  @doc "Serialize the board as a FEN string."
  @spec to_fen(t()) :: String.t()
  def to_fen(board), do: Features.Chess.FEN.to_fen(board)

  defp empty_pieces do
    for {color, type} <- @pieces_list, into: %{}, do: {{color, type}, 0}
  end

  defp color_bb(pieces, color) do
    Enum.reduce(@types, 0, fn type, acc -> acc ||| Map.fetch!(pieces, {color, type}) end)
  end

  defp slider_attacked?(board, color, rays, types) do
    occupancy = occupancy(board)

    Enum.any?(rays, fn ray ->
      case AttackTables.first_blocker(ray, occupancy) do
        nil ->
          false

        blocker ->
          case piece_at(board, blocker) do
            {piece_color, type} -> piece_color == color and type in types
            nil -> false
          end
      end
    end)
  end

  defp capture_target(board, color, :pawns, to) do
    if to == board.en_passant and piece_at(board, to) == nil do
      offset = if color == :white, do: -8, else: 8
      {{opposite(color), :pawns}, to + offset}
    else
      capture_at(board, to)
    end
  end

  defp capture_target(board, _color, _type, to), do: capture_at(board, to)

  defp capture_at(board, to) do
    case piece_at(board, to) do
      nil -> {nil, nil}
      piece -> {piece, to}
    end
  end

  defp remove_captured(pieces, nil, _square), do: pieces

  defp remove_captured(pieces, {color, type}, square) do
    remove_piece(pieces, color, type, square)
  end

  defp remove_piece(pieces, color, type, square) do
    Map.update!(pieces, {color, type}, &(&1 &&& bnot(1 <<< square)))
  end

  defp place_piece(pieces, color, type, square) do
    Map.update!(pieces, {color, type}, &(&1 ||| 1 <<< square))
  end

  defp move_castle_rook(pieces, color, :kings, from, to) when abs(to - from) == 2 do
    rook_from = if to > from, do: from + 3, else: from - 4
    rook_to = if to > from, do: to - 1, else: to + 1

    pieces
    |> remove_piece(color, :rooks, rook_from)
    |> place_piece(color, :rooks, rook_to)
  end

  defp move_castle_rook(pieces, _color, _type, _from, _to), do: pieces

  defp en_passant_square(:pawns, from, to) when abs(to - from) == 16 do
    div(from + to, 2)
  end

  defp en_passant_square(_type, _from, _to), do: nil

  defp update_castling(castling, from, to) do
    castling
    |> clear_castling(from)
    |> clear_castling(to)
  end

  defp clear_castling(castling, square) do
    case square do
      0 -> castling &&& bnot(@castle_wq)
      4 -> castling &&& bnot(@castle_wk ||| @castle_wq)
      7 -> castling &&& bnot(@castle_wk)
      56 -> castling &&& bnot(@castle_bq)
      60 -> castling &&& bnot(@castle_bk ||| @castle_bq)
      63 -> castling &&& bnot(@castle_bk)
      _ -> castling
    end
  end

  defp maybe_flag(acc, castling, flag, letter) do
    if (castling &&& flag) == 0, do: acc, else: acc <> letter
  end
end
