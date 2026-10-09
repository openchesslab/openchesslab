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

  alias Chess.Bitboard
  alias Chess.Board
  alias Chess.Move

  @type castling_right ::
          :white_kingside
          | :white_queenside
          | :black_kingside
          | :black_queenside

  @type t :: %__MODULE__{
          board: Board.t(),
          side_to_move: Board.color(),
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
      board: Board.empty(),
      side_to_move: :white,
      castling_rights: MapSet.new(),
      en_passant: nil
    }
  end

  def new(opts) do
    %__MODULE__{
      board: Keyword.get(opts, :board, Board.empty()),
      side_to_move: Keyword.get(opts, :side_to_move, :white),
      castling_rights: Keyword.get(opts, :castling_rights, MapSet.new()),
      en_passant: Keyword.get(opts, :en_passant)
    }
  end

  def starting_position do
    board =
      Board.empty()
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
    Board.get(board, square)
  end

  def put_piece(%__MODULE__{board: board} = position, square, piece) do
    %{position | board: Board.put(board, square, piece)}
  end

  def remove_piece(%__MODULE__{board: board} = position, square) do
    %{position | board: Board.remove(board, square)}
  end

  def pieces(%__MODULE__{board: board}) do
    Board.pieces(board)
  end

  def apply_move(%__MODULE__{side_to_move: side} = position, %Move{
        from: from,
        to: to,
        promotion: promotion
      }) do
    if opposing_king_at?(position, to, side) do
      {:error, :illegal_move}
    else
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
  end

  def apply_move(_position, _move) do
    {:error, :illegal_move}
  end

  defp opposing_king_at?(position, square, side) do
    piece_at(position, square) == {opposite_color(side), :king}
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

        promotion_pieces =
          if promotion_move?(piece, from) do
            [:queen, :rook, :bishop, :knight]
          else
            [nil]
          end

        destinations
        |> destination_squares()
        |> Enum.flat_map(fn to ->
          promotion_pieces
          |> Enum.reduce([], fn promotion_piece, acc ->
            move = Move.new(from, to, promotion_piece)

            if legal_pseudo_move?(
                 bitboard,
                 side,
                 king_square,
                 move,
                 piece
               ) do
              [move | acc]
            else
              acc
            end
          end)
          |> Enum.reverse()
        end)
      end)

    special_moves =
      position
      |> special_candidate_moves()
      |> Enum.filter(fn move ->
        match?({:ok, _}, apply_move(position, move))
      end)

    pseudo_moves ++ special_moves
  end

  # Enumerate set bits, stopping after the highest set destination.
  # Preserve ascending squares for SAN and other callers of legal_moves/1.
  defp destination_squares(mask), do: destination_squares(mask, 0, [])

  defp destination_squares(0, _square, reversed), do: Enum.reverse(reversed)

  defp destination_squares(mask, square, reversed) do
    reversed =
      if Bitwise.band(mask, 1) == 0 do
        reversed
      else
        [square | reversed]
      end

    destination_squares(Bitwise.bsr(mask, 1), square + 1, reversed)
  end

  @spec validate(t()) :: :ok | {:error, [atom()]}
  def validate(%__MODULE__{} = position) do
    errors =
      []
      |> validate_king_count(position, :white)
      |> validate_king_count(position, :black)
      |> validate_adjacent_kings(position)
      |> validate_pawns(position)
      |> validate_check_state(position)
      |> validate_castling_rights(position)
      |> validate_en_passant(position)
      |> validate_side_to_move(position)
      |> validate_material(position)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_king_count(errors, position, color) do
    count =
      Enum.count(pieces(position), fn
        {_square, {^color, :king}} -> true
        _ -> false
      end)

    if count == 1 do
      errors
    else
      [king_count_error(color) | errors]
    end
  end

  defp king_count_error(:white), do: :invalid_white_king_count
  defp king_count_error(:black), do: :invalid_black_king_count

  defp validate_adjacent_kings(errors, position) do
    with white when not is_nil(white) <- king_square(position, :white),
         black when not is_nil(black) <- king_square(position, :black) do
      file_distance = abs(rem(white, 8) - rem(black, 8))
      rank_distance = abs(div(white, 8) - div(black, 8))

      if file_distance <= 1 and rank_distance <= 1 do
        [:adjacent_kings | errors]
      else
        errors
      end
    else
      _ -> errors
    end
  end

  defp validate_en_passant(errors, %{en_passant: nil}) do
    errors
  end

  defp validate_en_passant(errors, position) do
    if valid_en_passant?(position) do
      errors
    else
      [:invalid_en_passant | errors]
    end
  end

  defp valid_en_passant?(%{side_to_move: :white, en_passant: target} = position)
       when target in 40..47 do
    moved_pawn_square = target - 8
    file = rem(moved_pawn_square, 8)

    piece_at(position, target) == nil and
      piece_at(position, moved_pawn_square) == {:black, :pawn} and
      adjacent_pawn?(position, moved_pawn_square, file, {:white, :pawn})
  end

  defp valid_en_passant?(%{side_to_move: :black, en_passant: target} = position)
       when target in 16..23 do
    moved_pawn_square = target + 8
    file = rem(moved_pawn_square, 8)

    piece_at(position, target) == nil and
      piece_at(position, moved_pawn_square) == {:white, :pawn} and
      adjacent_pawn?(position, moved_pawn_square, file, {:black, :pawn})
  end

  defp valid_en_passant?(_position), do: false

  defp adjacent_pawn?(position, pawn_square, file, pawn) do
    left? =
      file > 0 and
        piece_at(position, pawn_square - 1) == pawn

    right? =
      file < 7 and
        piece_at(position, pawn_square + 1) == pawn

    left? or right?
  end

  defp validate_pawns(errors, position) do
    invalid? =
      Enum.any?(pieces(position), fn
        {square, {_color, :pawn}} ->
          square in 0..7 or square in 56..63

        _ ->
          false
      end)

    if invalid? do
      [:pawn_on_back_rank | errors]
    else
      errors
    end
  end

  defp validate_check_state(errors, position) do
    white_king = king_square(position, :white)
    black_king = king_square(position, :black)

    if valid_king_configuration?(white_king, black_king) do
      inactive_color = opposite_color(position.side_to_move)

      if in_check?(position, inactive_color) do
        [:inactive_king_in_check | errors]
      else
        errors
      end
    else
      errors
    end
  end

  defp valid_king_configuration?(nil, _black), do: false
  defp valid_king_configuration?(_white, nil), do: false

  defp valid_king_configuration?(white, black) do
    file_distance = abs(rem(white, 8) - rem(black, 8))
    rank_distance = abs(div(white, 8) - div(black, 8))

    file_distance > 1 or rank_distance > 1
  end

  @castling_right_squares %{
    white_kingside: {4, 7, :white},
    white_queenside: {4, 0, :white},
    black_kingside: {60, 63, :black},
    black_queenside: {60, 56, :black}
  }

  @doc """
  The subset of `castling_rights` that is consistent with the current
  king/rook placement. Validation requires the claimed rights to be a
  subset of this; board-edit normalization prunes a position's rights
  to it (moving a rook away drops the corresponding right).
  """
  @spec structurally_valid_castling_rights(t()) :: MapSet.t()
  def structurally_valid_castling_rights(%__MODULE__{} = position) do
    for {right, {king_square, rook_square, color}} <- @castling_right_squares,
        piece_at(position, king_square) == {color, :king},
        piece_at(position, rook_square) == {color, :rook},
        into: MapSet.new(),
        do: right
  end

  defp validate_castling_rights(errors, position) do
    if MapSet.subset?(
         position.castling_rights,
         structurally_valid_castling_rights(position)
       ) do
      errors
    else
      [:invalid_castling_rights | errors]
    end
  end

  defp validate_side_to_move(errors, %{side_to_move: side_to_move})
       when side_to_move in [:white, :black] do
    errors
  end

  defp validate_side_to_move(errors, _position) do
    [:invalid_side_to_move | errors]
  end

  defp validate_material(errors, position) do
    Enum.reduce([:white, :black], errors, fn color, errors ->
      validate_material(errors, position, color)
    end)
  end

  defp validate_material(errors, position, color) do
    counts =
      position
      |> pieces()
      |> Enum.reduce(%{}, fn
        {_square, {^color, piece}}, counts ->
          Map.update(counts, piece, 1, &(&1 + 1))

        _, counts ->
          counts
      end)

    pawn_count = Map.get(counts, :pawn, 0)

    cond do
      pawn_count > 8 ->
        [:too_many_pawns | errors]

      required_promotions(counts) > 8 - pawn_count ->
        [:impossible_promotions | errors]

      true ->
        errors
    end
  end

  defp required_promotions(counts) do
    extra(counts, :queen, 1) +
      extra(counts, :rook, 2) +
      extra(counts, :bishop, 2) +
      extra(counts, :knight, 2)
  end

  defp extra(counts, piece, initial_count) do
    max(Map.get(counts, piece, 0) - initial_count, 0)
  end

  defp legal_pseudo_move?(bitboard, side, king_square, move, piece) do
    if Bitboard.get(bitboard, move.to) == {opposite_color(side), :king} do
      false
    else
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

      {7, {:white, _piece}} when rem(from, 8) < 7 ->
        capture_pawn(position, from, to, :black, :white, promotion)

      {9, {:white, _piece}} when rem(from, 8) > 0 ->
        capture_pawn(position, from, to, :black, :white, promotion)

      {7, nil} when rem(from, 8) < 7 ->
        en_passant_capture(position, :black, from, to, :white)

      {9, nil} when rem(from, 8) > 0 ->
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
         false <- attacked?(position, opponent, castling_cross_square(right)),
         false <- attacked?(position, opponent, king_to) do
      position =
        position
        |> remove_piece(king_from)
        |> remove_piece(rook_from)
        |> put_piece(king_to, {color, :king})
        |> put_piece(rook_to, {color, :rook})
        |> remove_castling_rights_for_color(color)

      {:ok,
       %{
         position
         | side_to_move: opponent,
           en_passant: nil
       }}
    else
      _ ->
        {:error, :illegal_move}
    end
  end

  defp remove_castling_rights_for_color(position, :white) do
    position
    |> remove_castling_right(:white_kingside)
    |> remove_castling_right(:white_queenside)
  end

  defp remove_castling_rights_for_color(position, :black) do
    position
    |> remove_castling_right(:black_kingside)
    |> remove_castling_right(:black_queenside)
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

  defp castling_cross_square(:white_kingside) do
    5
  end

  defp castling_cross_square(:white_queenside) do
    3
  end

  defp castling_cross_square(:black_kingside) do
    61
  end

  defp castling_cross_square(:black_queenside) do
    59
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

    (from + step)
    |> Stream.iterate(&(&1 + step))
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

  defp update_castling_rights_for_capture(position, 7, {:white, :rook}) do
    remove_castling_right(position, :white_kingside)
  end

  defp update_castling_rights_for_capture(position, 0, {:white, :rook}) do
    remove_castling_right(position, :white_queenside)
  end

  defp update_castling_rights_for_capture(position, 63, {:black, :rook}) do
    remove_castling_right(position, :black_kingside)
  end

  defp update_castling_rights_for_capture(position, 56, {:black, :rook}) do
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
    captured_piece = piece_at(position, to)

    position =
      position
      |> remove_piece(from)
      |> put_piece(to, {color, promotion})
      |> update_castling_rights_for_capture(to, captured_piece)

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
    end
  end

  defp en_passant_target(position, :black, from, to) do
    if from - to == 16 and adjacent_enemy_pawn?(position, to, :white) do
      from - 8
    end
  end

  defp en_passant_capture(position, :white, from, to, :black) do
    do_en_passant_capture(
      position,
      from,
      to,
      to - 8,
      :black
    )
  end

  defp en_passant_capture(position, :black, from, to, :white) do
    do_en_passant_capture(
      position,
      from,
      to,
      to + 8,
      :white
    )
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

  defp update_castling_rights_for_move(position, :white, {:white, :king}, _from) do
    position
    |> remove_castling_right(:white_kingside)
    |> remove_castling_right(:white_queenside)
  end

  defp update_castling_rights_for_move(position, :black, {:black, :king}, _from) do
    position
    |> remove_castling_right(:black_kingside)
    |> remove_castling_right(:black_queenside)
  end

  defp update_castling_rights_for_move(position, :white, {:white, :rook}, 7) do
    remove_castling_right(position, :white_kingside)
  end

  defp update_castling_rights_for_move(position, :white, {:white, :rook}, 0) do
    remove_castling_right(position, :white_queenside)
  end

  defp update_castling_rights_for_move(position, :black, {:black, :rook}, 63) do
    remove_castling_right(position, :black_kingside)
  end

  defp update_castling_rights_for_move(position, :black, {:black, :rook}, 56) do
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
      Board.put(board, rank_start + offset, {color, type})
    end)
  end

  defp place_pawns(board, color, rank_start) do
    Enum.reduce(0..7, board, fn offset, board ->
      Board.put(board, rank_start + offset, {color, :pawn})
    end)
  end

  @doc """
  Decode a position from the SPA's wire format.

      %{
        "pieces": [[0, "white_rook"], [12, "white_pawn"], ...],
        "side_to_move": "white" | "black",
        "castling_rights": ["white_kingside", ...],
        "en_passant": 28 | nil
      }

  Used by the SolidJS SPA's position editor and other JSON-write
  endpoints. Validates via `Chess.Position.validate/1` and returns the
  underlying error structure so the controller can surface the
  failure reasons as 422.
  """
  @spec from_wire(map()) :: {:ok, t()} | {:error, [atom()]}
  def from_wire(wire) do
    with {:ok, board} <- decode_board(wire),
         {:ok, side} <- decode_side(wire["side_to_move"]),
         {:ok, rights} <- decode_castling(wire["castling_rights"] || []),
         {:ok, en_passant} <- decode_en_passant(wire["en_passant"]) do
      position = %__MODULE__{
        board: board,
        side_to_move: side,
        castling_rights: rights,
        en_passant: en_passant
      }

      case Chess.Position.validate(position) do
        :ok -> {:ok, position}
        {:error, reasons} -> {:error, reasons}
      end
    else
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp decode_board(%{"pieces" => pieces}) when is_list(pieces) do
    Enum.reduce_while(pieces, {:ok, Board.empty()}, fn [sq, str], acc ->
      with {:ok, board} <- acc,
           {:ok, piece} <- decode_piece(str),
           true <- is_integer(sq) and sq >= 0 and sq <= 63 do
        {:cont, {:ok, Board.put(board, sq, piece)}}
      else
        _ -> {:halt, {:error, :bad_pieces}}
      end
    end)
  end

  defp decode_board(_), do: {:error, :bad_pieces}

  @doc """
  Decodes a wire piece string (`"white_pawn"`) into `{:color, kind}`.

  Public because the SPA sends single pieces for placement edits (e.g.
  putting a knight on a square); `from_wire/1` uses the same decoder
  for whole boards.
  """
  @spec decode_piece(String.t()) ::
          {:ok, Board.piece()} | {:error, :bad_piece}
  def decode_piece(str) when is_binary(str) do
    case String.split(str, "_", parts: 2) do
      [color_str, kind_str] ->
        color =
          case color_str do
            "white" -> :white
            "black" -> :black
            _ -> nil
          end

        kind =
          case kind_str do
            "pawn" -> :pawn
            "knight" -> :knight
            "bishop" -> :bishop
            "rook" -> :rook
            "queen" -> :queen
            "king" -> :king
            _ -> nil
          end

        if color && kind, do: {:ok, {color, kind}}, else: {:error, :bad_piece}

      _ ->
        {:error, :bad_piece}
    end
  end

  def decode_piece(_str), do: {:error, :bad_piece}

  defp decode_side("white"), do: {:ok, :white}
  defp decode_side("black"), do: {:ok, :black}
  defp decode_side(_), do: {:error, :bad_side}

  defp decode_castling(list) when is_list(list) do
    rights =
      Enum.reduce_while(list, MapSet.new(), fn str, acc ->
        case str do
          "white_kingside" -> {:cont, MapSet.put(acc, :white_kingside)}
          "white_queenside" -> {:cont, MapSet.put(acc, :white_queenside)}
          "black_kingside" -> {:cont, MapSet.put(acc, :black_kingside)}
          "black_queenside" -> {:cont, MapSet.put(acc, :black_queenside)}
          _ -> {:halt, :bad_castling_rights}
        end
      end)

    case rights do
      {:error, reason} -> {:error, reason}
      set -> {:ok, set}
    end
  end

  defp decode_castling(_), do: {:error, :bad_castling_rights}

  defp decode_en_passant(nil), do: {:ok, nil}

  defp decode_en_passant(n) when is_integer(n) and n >= 0 and n <= 63, do: {:ok, n}

  defp decode_en_passant(_), do: {:error, :bad_en_passant}

  @doc """
  Encode a position as the SPA's wire format. Mirrors `from_wire/1`:

      %{
        "pieces" => [[0, "white_rook"], [12, "white_pawn"], ...],
        "side_to_move" => "white" | "black",
        "castling_rights" => ["white_kingside", ...],
        "en_passant" => 28 | nil
      }

  Top-level keys AND values are strings — the shape matches the JSON
  the SPA sends and the shape `from_wire/1` parses, so

      from_wire(to_wire(p)) == {:ok, p}

  for any valid position. Jason encodes this map directly (atoms in
  piece strings like `"white_pawn"` are already strings). Pieces are
  sorted by square for stable output across runs.

  Used by the SolidJS SPA's read-only render path (Phase 2c) and
  available to anything else that needs the same shape `from_wire/1`
  accepts.
  """
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = position) do
    %{
      "pieces" => pieces_for_wire(position),
      "side_to_move" => Atom.to_string(position.side_to_move),
      "castling_rights" => Enum.map(position.castling_rights, &Atom.to_string/1),
      "en_passant" => position.en_passant
    }
  end

  defp pieces_for_wire(%__MODULE__{board: board}) do
    board
    |> Board.pieces()
    |> Enum.map(fn {square, {color, kind}} -> [square, "#{color}_#{kind}"] end)
    |> Enum.sort_by(fn [square, _piece] -> square end)
  end

  defp do_en_passant_capture(position, from, to, captured_square, captured_color) do
    if position.en_passant == to and
         piece_at(position, captured_square) ==
           {captured_color, :pawn} do
      piece =
        piece_at(
          position,
          from
        )

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
  end
end
