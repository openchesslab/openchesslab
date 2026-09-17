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

  alias Chess.Board
  alias Chess.Bitboard
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
    result =
      case piece_at(position, from) do
        {^side, :pawn} ->
          apply_pawn_move(position, side, from, to, promotion)

        {^side, :king} ->
          apply_king_move(position, side, from, to, promotion)

        {^side, :rook} ->
          apply_rook_move(position, side, from, to, promotion)

        {^side, :bishop} ->
          apply_bishop_move(position, side, from, to, promotion)

        {^side, :knight} ->
          apply_knight_move(position, side, from, to, promotion)

        {^side, :queen} ->
          apply_queen_move(position, side, from, to, promotion)

        _ ->
          {:error, :illegal_move}
      end

    case result do
      {:ok, new_position} ->
        if in_check?(new_position, side) do
          {:error, :illegal_move}
        else
          {:ok, new_position}
        end

      error ->
        error
    end
  end

  def apply_move(_position, _move) do
    {:error, :illegal_move}
  end

  def in_check?(position, color) when color in [:white, :black] do
    king_square =
      position.board
      |> Board.pieces()
      |> Enum.find_value(fn
        {square, {^color, :king}} -> square
        _ -> nil
      end)

    case king_square do
      nil ->
        false

      square ->
        position
        |> Bitboard.from_position()
        |> Bitboard.attacked?(opposite_color(color), square)
    end
  end

  def legal_moves(position) do
    bitboard = Bitboard.from_position(position)
    side = position.side_to_move
    king_square = king_square(position, side)

    pseudo_moves =
      bitboard
      |> Bitboard.pseudo_moves(side)
      |> Enum.flat_map(fn {from, destinations} ->
        piece = piece_at(position, from)

        for to <- 0..63,
            Bitwise.band(destinations, Bitwise.bsl(1, to)) != 0 do
          promotion =
            if promotion_move?(piece, from) do
              [:queen, :rook, :bishop, :knight]
            else
              [nil]
            end

          for promotion_piece <- promotion do
            move = Move.new(from, to, promotion_piece)

            if legal_pseudo_move?(
                 bitboard,
                 side,
                 king_square,
                 move,
                 piece
               ) do
              move
            else
              nil
            end
          end
        end
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      end)

    special_moves =
      position
      |> special_candidate_moves()
      |> Enum.filter(fn move ->
        match?({:ok, _}, apply_move(position, move))
      end)

    pseudo_moves ++ special_moves
  end

  defp legal_pseudo_move?(
         bitboard,
         side,
         king_square,
         move,
         piece
       ) do
    next_bitboard = Bitboard.after_move(bitboard, move, piece)

    king_square =
      case piece do
        {^side, :king} ->
          move.to

        _ ->
          king_square
      end

    not Bitboard.attacked?(
      next_bitboard,
      opposite_color(side),
      king_square
    )
  end

  defp king_square(position, color) do
    position.board
    |> Board.pieces()
    |> Enum.find_value(fn
      {square, {^color, :king}} -> square
      _ -> nil
    end)
  end

  defp special_candidate_moves(position) do
    castling_moves =
      case position.side_to_move do
        :white ->
          [Move.new(4, 6), Move.new(4, 2)]

        :black ->
          [Move.new(60, 62), Move.new(60, 58)]
      end

    en_passant_moves =
      case position.en_passant do
        nil ->
          []

        target ->
          en_passant_candidate_moves(position, target)
      end

    castling_moves ++ en_passant_moves
  end

  defp en_passant_candidate_moves(%{side_to_move: :white}, target) do
    [target - 7, target - 9]
    |> Enum.filter(&(&1 in 0..63))
    |> Enum.map(&Move.new(&1, target))
  end

  defp en_passant_candidate_moves(%{side_to_move: :black}, target) do
    [target + 7, target + 9]
    |> Enum.filter(&(&1 in 0..63))
    |> Enum.map(&Move.new(&1, target))
  end

  def checkmate?(position, color) do
    in_check?(position, color) and
      legal_moves(%{position | side_to_move: color}) == []
  end

  def stalemate?(position, color) do
    not in_check?(position, color) and
      legal_moves(%{position | side_to_move: color}) == []
  end

  defp promotion_move?({:white, :pawn}, square), do: square in 48..55
  defp promotion_move?({:black, :pawn}, square), do: square in 8..15
  defp promotion_move?(_piece, _square), do: false

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
    if abs(to - from) == 2 do
      apply_castling_move(position, color, from, to)
    else
      apply_normal_king_move(position, color, from, to)
    end
  end

  defp apply_king_move(_position, _color, _from, _to, _promotion) do
    {:error, :illegal_move}
  end

  defp apply_normal_king_move(position, color, from, to) do
    file_distance = abs(rem(to, 8) - rem(from, 8))
    rank_distance = abs(div(to, 8) - div(from, 8))

    if file_distance <= 1 and rank_distance <= 1 and
         file_distance + rank_distance > 0 do
      case piece_at(position, to) do
        {^color, _piece} ->
          {:error, :illegal_move}

        _ ->
          move_piece(
            position,
            from,
            to,
            color,
            opposite_color(color)
          )
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_castling_move(position, :white, 4, 6) do
    castle(position, :white, :white_kingside, 7, 5, 6)
  end

  defp apply_castling_move(position, :white, 4, 2) do
    castle(position, :white, :white_queenside, 0, 3, 2)
  end

  defp apply_castling_move(position, :black, 60, 62) do
    castle(position, :black, :black_kingside, 63, 61, 62)
  end

  defp apply_castling_move(position, :black, 60, 58) do
    castle(position, :black, :black_queenside, 56, 59, 58)
  end

  defp apply_castling_move(_position, _color, _from, _to) do
    {:error, :illegal_move}
  end

  defp castle(position, color, right, rook_from, rook_to, king_to) do
    opponent = opposite_color(color)
    king_from = if color == :white, do: 4, else: 60

    with true <- MapSet.member?(position.castling_rights, right),
         {^color, :king} <- piece_at(position, king_from),
         {^color, :rook} <- piece_at(position, rook_from),
         true <- castling_path_clear?(position, right),
         false <- in_check?(position, color),
         false <- attacked?(position, opponent, castling_cross_square(color)),
         false <- attacked?(position, opponent, king_to) do
      position =
        position
        |> remove_piece(king_from)
        |> remove_piece(rook_from)
        |> put_piece(king_to, {color, :king})
        |> put_piece(rook_to, {color, :rook})

      {:ok,
       %{
         position
         | side_to_move: opponent,
           en_passant: nil,
           castling_rights:
             MapSet.delete(
               position.castling_rights,
               right
             )
       }}
    else
      _ ->
        {:error, :illegal_move}
    end
  end

  defp castling_path_clear?(position, :white_kingside) do
    piece_at(position, 5) == nil and
      piece_at(position, 6) == nil
  end

  defp castling_path_clear?(position, :white_queenside) do
    piece_at(position, 1) == nil and
      piece_at(position, 2) == nil and
      piece_at(position, 3) == nil
  end

  defp castling_path_clear?(position, :black_kingside) do
    piece_at(position, 61) == nil and
      piece_at(position, 62) == nil
  end

  defp castling_path_clear?(position, :black_queenside) do
    piece_at(position, 57) == nil and
      piece_at(position, 58) == nil and
      piece_at(position, 59) == nil
  end

  defp castling_cross_square(:white) do
    5
  end

  defp castling_cross_square(:black) do
    61
  end

  defp attacked?(position, color, square) do
    position
    |> Bitboard.from_position()
    |> Bitboard.attacked?(color, square)
  end

  defp apply_rook_move(position, color, from, to, nil) do
    same_file = rem(from, 8) == rem(to, 8)
    same_rank = div(from, 8) == div(to, 8)

    if same_file or same_rank do
      if path_clear?(position, from, to) do
        case piece_at(position, to) do
          {^color, _piece} ->
            {:error, :illegal_move}

          {_, _piece} ->
            capture_piece(position, from, to, opposite_color(color))

          nil ->
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

  defp apply_bishop_move(position, color, from, to, nil) do
    file_distance = abs(rem(to, 8) - rem(from, 8))
    rank_distance = abs(div(to, 8) - div(from, 8))

    if file_distance == rank_distance and file_distance > 0 do
      if path_clear?(position, from, to) do
        case piece_at(position, to) do
          {^color, _piece} ->
            {:error, :illegal_move}

          _ ->
            move_piece(
              position,
              from,
              to,
              color,
              opposite_color(color)
            )
        end
      else
        {:error, :illegal_move}
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_bishop_move(_position, _color, _from, _to, _promotion) do
    {:error, :illegal_move}
  end

  defp apply_knight_move(position, color, from, to, nil) do
    file_distance = abs(rem(to, 8) - rem(from, 8))
    rank_distance = abs(div(to, 8) - div(from, 8))

    valid_move =
      (file_distance == 1 and rank_distance == 2) or
        (file_distance == 2 and rank_distance == 1)

    if valid_move do
      case piece_at(position, to) do
        {^color, _piece} ->
          {:error, :illegal_move}

        _ ->
          move_piece(
            position,
            from,
            to,
            color,
            opposite_color(color)
          )
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_knight_move(_position, _color, _from, _to, _promotion) do
    {:error, :illegal_move}
  end

  defp apply_queen_move(position, color, from, to, nil) do
    file_distance = abs(rem(to, 8) - rem(from, 8))
    rank_distance = abs(div(to, 8) - div(from, 8))

    valid_move =
      file_distance == 0 or
        rank_distance == 0 or
        file_distance == rank_distance

    if valid_move and file_distance + rank_distance > 0 do
      if path_clear?(position, from, to) do
        case piece_at(position, to) do
          {^color, _piece} ->
            {:error, :illegal_move}

          _ ->
            move_piece(
              position,
              from,
              to,
              color,
              opposite_color(color)
            )
        end
      else
        {:error, :illegal_move}
      end
    else
      {:error, :illegal_move}
    end
  end

  defp apply_queen_move(_position, _color, _from, _to, _promotion) do
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

  defp movement_step(from, to) do
    file_from = rem(from, 8)
    file_to = rem(to, 8)

    cond do
      to > from and file_to > file_from -> 9
      to > from -> 7
      file_to > file_from -> -7
      true -> -9
    end
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
    captured_piece = piece_at(position, to)

    position =
      position
      |> remove_piece(from)
      |> put_piece(to, piece)
      |> update_castling_rights_for_capture(to, captured_piece)

    {:ok,
     %{
       position
       | side_to_move: next_side,
         en_passant: nil
     }}
  end

  defp update_castling_rights_for_capture(
         position,
         7,
         {:white, :rook}
       ) do
    remove_castling_right(position, :white_kingside)
  end

  defp update_castling_rights_for_capture(
         position,
         0,
         {:white, :rook}
       ) do
    remove_castling_right(position, :white_queenside)
  end

  defp update_castling_rights_for_capture(
         position,
         63,
         {:black, :rook}
       ) do
    remove_castling_right(position, :black_kingside)
  end

  defp update_castling_rights_for_capture(
         position,
         56,
         {:black, :rook}
       ) do
    remove_castling_right(position, :black_queenside)
  end

  defp update_castling_rights_for_capture(position, _square, _piece) do
    position
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

  defp move_piece(position, from, to, color, next_side) do
    piece = piece_at(position, from)
    captured_piece = piece_at(position, to)

    position =
      position
      |> remove_piece(from)
      |> put_piece(to, piece)
      |> update_castling_rights_for_move(color, piece, from)
      |> update_castling_rights_for_capture(to, captured_piece)

    {:ok,
     %{
       position
       | side_to_move: next_side,
         en_passant: nil
     }}
  end

  defp update_castling_rights_for_move(
         position,
         :white,
         {:white, :king},
         _from
       ) do
    position
    |> remove_castling_right(:white_kingside)
    |> remove_castling_right(:white_queenside)
  end

  defp update_castling_rights_for_move(
         position,
         :black,
         {:black, :king},
         _from
       ) do
    position
    |> remove_castling_right(:black_kingside)
    |> remove_castling_right(:black_queenside)
  end

  defp update_castling_rights_for_move(
         position,
         :white,
         {:white, :rook},
         7
       ) do
    remove_castling_right(position, :white_kingside)
  end

  defp update_castling_rights_for_move(
         position,
         :white,
         {:white, :rook},
         0
       ) do
    remove_castling_right(position, :white_queenside)
  end

  defp update_castling_rights_for_move(
         position,
         :black,
         {:black, :rook},
         63
       ) do
    remove_castling_right(position, :black_kingside)
  end

  defp update_castling_rights_for_move(
         position,
         :black,
         {:black, :rook},
         56
       ) do
    remove_castling_right(position, :black_queenside)
  end

  defp update_castling_rights_for_move(position, _color, _piece, _from) do
    position
  end

  defp remove_castling_right(position, right) do
    %{position | castling_rights: MapSet.delete(position.castling_rights, right)}
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
