defmodule Chess.Position do
  @moduledoc """
  Represents a chess position.

  A position is defined by:

    * the pieces on the board
    * the side to move
    * the castling rights
    * the en passant target square, when an en passant capture is available

  Halfmove and fullmove counters are not part of position identity.
  """

  alias Chess.Move

  @type castling_right ::
          :white_kingside
          | :white_queenside
          | :black_kingside
          | :black_queenside

  @type t :: %__MODULE__{
          board: Chess.Board.t(),
          side_to_move: Chess.Board.color(),
          castling_rights: MapSet.t(castling_right()),
          en_passant: Chess.Square.t() | nil
        }

  @enforce_keys [:board, :side_to_move, :castling_rights, :en_passant]

  defstruct [
    :board,
    :side_to_move,
    :castling_rights,
    :en_passant
  ]

  def new do
    %__MODULE__{
      board: Chess.Board.empty(),
      side_to_move: :white,
      castling_rights: MapSet.new(),
      en_passant: nil
    }
  end

  def new(opts) do
    %__MODULE__{
      board: Keyword.get(opts, :board, Chess.Board.empty()),
      side_to_move: Keyword.get(opts, :side_to_move, :white),
      castling_rights: Keyword.get(opts, :castling_rights, MapSet.new()),
      en_passant: Keyword.get(opts, :en_passant)
    }
  end

  def starting_position do
    board =
      Chess.Board.empty()
      |> place_back_rank(:white, 0)
      |> place_pawns(:white, 8)
      |> place_back_rank(:black, 56)
      |> place_pawns(:black, 48)

    %__MODULE__{
      board: board,
      side_to_move: :white,
      castling_rights:
        MapSet.new([
          :white_kingside,
          :white_queenside,
          :black_kingside,
          :black_queenside
        ]),
      en_passant: nil
    }
  end

  def piece_at(%__MODULE__{board: board}, square) do
    Chess.Board.get(board, square)
  end

  def put_piece(%__MODULE__{board: board} = position, square, piece) do
    %{position | board: Chess.Board.put(board, square, piece)}
  end

  def remove_piece(%__MODULE__{board: board} = position, square) do
    %{position | board: Chess.Board.remove(board, square)}
  end

  def pieces(%__MODULE__{board: board}) do
    Chess.Board.pieces(board)
  end

  def apply_move(
        %__MODULE__{side_to_move: side} = position,
        %Move{from: from, to: to, promotion: promotion}
      ) do
    case piece_at(position, from) do
      {^side, :pawn} ->
        apply_pawn_move(position, side, from, to, promotion)

      {^side, :king} ->
        apply_king_move(position, side, from, to, promotion)

      {^side, :rook} ->
        apply_rook_move(position, side, from, to, promotion)

      _ ->
        {:error, :illegal_move}
    end
  end

  def apply_move(_position, _move) do
    {:error, :illegal_move}
  end

  defp apply_pawn_move(position, :white, from, to, promotion) do
    case {to - from, piece_at(position, to)} do
      {8, nil} ->
        move_pawn(position, from, to, :white, :black, promotion)

      {16, nil} when from in 8..15 ->
        intermediate = from + 8

        if piece_at(position, intermediate) == nil do
          move_pawn(position, from, to, :white, :black, nil)
        else
          {:error, :illegal_move}
        end

      {7, {:black, _piece}} when rem(from, 8) > 0 ->
        capture_pawn(position, from, to, :white, :black, promotion)

      {9, {:black, _piece}} when rem(from, 8) < 7 ->
        capture_pawn(position, from, to, :white, :black, promotion)

      {7, nil} when rem(from, 8) > 0 ->
        en_passant_capture(position, :white, from, to, :black)

      {9, nil} when rem(from, 8) < 7 ->
        en_passant_capture(position, :white, from, to, :black)

      _ ->
        {:error, :illegal_move}
    end
  end

  defp apply_pawn_move(position, :black, from, to, promotion) do
    case {from - to, piece_at(position, to)} do
      {8, nil} ->
        move_pawn(position, from, to, :black, :white, promotion)

      {16, nil} when from in 48..55 ->
        intermediate = from - 8

        if piece_at(position, intermediate) == nil do
          move_pawn(position, from, to, :black, :white, nil)
        else
          {:error, :illegal_move}
        end

      {7, {:white, _piece}} when rem(from, 8) > 0 ->
        capture_pawn(position, from, to, :black, :white, promotion)

      {9, {:white, _piece}} when rem(from, 8) < 7 ->
        capture_pawn(position, from, to, :black, :white, promotion)

      {7, nil} when rem(from, 8) > 0 ->
        en_passant_capture(position, :black, from, to, :white)

      {9, nil} when rem(from, 8) < 7 ->
        en_passant_capture(position, :black, from, to, :white)

      _ ->
        {:error, :illegal_move}
    end
  end

  defp apply_king_move(position, color, from, to, nil) do
    file_distance = abs(rem(to, 8) - rem(from, 8))
    rank_distance = abs(div(to, 8) - div(from, 8))

    if file_distance <= 1 and rank_distance <= 1 and
         file_distance + rank_distance > 0 do
      case piece_at(position, to) do
        {^color, _piece} ->
          {:error, :illegal_move}

        _ ->
          move_piece(position, from, to, color, opposite_color(color))
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_king_move(_position, _color, _from, _to, _promotion) do
    {:error, :illegal_move}
  end

  defp apply_rook_move(position, color, from, to, nil) do
    same_file = rem(from, 8) == rem(to, 8)
    same_rank = div(from, 8) == div(to, 8)

    if same_file or same_rank do
      if path_clear?(position, from, to) do
        case piece_at(position, to) do
          {^color, _piece} ->
            {:error, :illegal_move}

          _ ->
            move_piece(position, from, to, color, opposite_color(color))
        end
      else
        {:error, :illegal_move}
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_rook_move(_position, _color, _from, _to, _promotion) do
    {:error, :illegal_move}
  end

  defp path_clear?(position, from, to) do
    step = movement_step(from, to)

    Stream.iterate(from + step, &(&1 + step))
    |> Enum.take_while(&(&1 != to))
    |> Enum.all?(fn square ->
      piece_at(position, square) == nil
    end)
  end

  defp movement_step(from, to) when rem(from, 8) == rem(to, 8) do
    if to > from, do: 8, else: -8
  end

  defp movement_step(from, to) when div(from, 8) == div(to, 8) do
    if to > from, do: 1, else: -1
  end

  defp move_pawn(position, from, to, color, next_side, promotion) do
    if promotion_required?(color, to) do
      promote_pawn(position, from, to, color, next_side, promotion)
    else
      if promotion == nil do
        en_passant = en_passant_target(position, color, from, to)

        position =
          position
          |> remove_piece(from)
          |> put_piece(to, {color, :pawn})

        {:ok,
         %{
           position
           | side_to_move: next_side,
             en_passant: en_passant
         }}
      else
        {:error, :illegal_move}
      end
    end
  end

  defp capture_pawn(position, from, to, color, next_side, promotion) do
    if promotion_required?(color, to) do
      promote_pawn(position, from, to, color, next_side, promotion)
    else
      if promotion == nil do
        capture_piece(position, from, to, next_side)
      else
        {:error, :illegal_move}
      end
    end
  end

  defp capture_piece(position, from, to, next_side) do
    piece = piece_at(position, from)

    position =
      position
      |> remove_piece(from)
      |> put_piece(to, piece)

    {:ok,
     %{
       position
       | side_to_move: next_side,
         en_passant: nil
     }}
  end

  defp promotion_required?(:white, to), do: to in 56..63
  defp promotion_required?(:black, to), do: to in 0..7

  defp promote_pawn(_position, _from, _to, _color, _next_side, nil) do
    {:error, :illegal_move}
  end

  defp promote_pawn(position, from, to, color, next_side, promotion)
       when promotion in [:queen, :rook, :bishop, :knight] do
    position =
      position
      |> remove_piece(from)
      |> put_piece(to, {color, promotion})

    {:ok,
     %{
       position
       | side_to_move: next_side,
         en_passant: nil
     }}
  end

  defp promote_pawn(_position, _from, _to, _color, _next_side, _promotion) do
    {:error, :illegal_move}
  end

  defp en_passant_target(position, :white, from, to) do
    if to - from == 16 and adjacent_enemy_pawn?(position, to, :black) do
      from + 8
    else
      nil
    end
  end

  defp en_passant_target(position, :black, from, to) do
    if from - to == 16 and adjacent_enemy_pawn?(position, to, :white) do
      from - 8
    else
      nil
    end
  end

  defp en_passant_capture(position, color, from, to, captured_color) do
    if position.en_passant == to do
      captured_square =
        case color do
          :white -> to - 8
          :black -> to + 8
        end

      if piece_at(position, captured_square) == {captured_color, :pawn} do
        piece = piece_at(position, from)

        position =
          position
          |> remove_piece(from)
          |> remove_piece(captured_square)
          |> put_piece(to, piece)

        {:ok,
         %{
           position
           | side_to_move: captured_color,
             en_passant: nil
         }}
      else
        {:error, :illegal_move}
      end
    else
      {:error, :illegal_move}
    end
  end

  defp adjacent_enemy_pawn?(position, square, enemy_color) do
    file = rem(square, 8)

    left =
      if file > 0 do
        piece_at(position, square - 1)
      end

    right =
      if file < 7 do
        piece_at(position, square + 1)
      end

    left == {enemy_color, :pawn} or right == {enemy_color, :pawn}
  end

  defp move_piece(position, from, to, _color, next_side) do
    piece = piece_at(position, from)

    position =
      position
      |> remove_piece(from)
      |> put_piece(to, piece)

    {:ok,
     %{
       position
       | side_to_move: next_side,
         en_passant: nil
     }}
  end

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white

  defp place_back_rank(board, color, rank_start) do
    pieces = [
      {0, :rook},
      {1, :knight},
      {2, :bishop},
      {3, :queen},
      {4, :king},
      {5, :bishop},
      {6, :knight},
      {7, :rook}
    ]

    Enum.reduce(pieces, board, fn {offset, type}, board ->
      Chess.Board.put(board, rank_start + offset, {color, type})
    end)
  end

  defp place_pawns(board, color, rank_start) do
    Enum.reduce(0..7, board, fn offset, board ->
      Chess.Board.put(board, rank_start + offset, {color, :pawn})
    end)
  end
end
