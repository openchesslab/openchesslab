defmodule Chess.PositionProperties do
  @moduledoc """
  Derived properties of a chess position.
  """

  alias Chess.Bitboard
  alias Chess.Position

  @piece_types [:pawn, :knight, :bishop, :rook, :queen, :king]

  @files [:a, :b, :c, :d, :e, :f, :g, :h]

  @board_mask 0xFFFFFFFFFFFFFFFF
  @not_a_file 0xFEFEFEFEFEFEFEFE
  @not_h_file 0x7F7F7F7F7F7F7F7F
  @white_opponent_half 0xFFFFFFFF00000000
  @black_opponent_half 0x00000000FFFFFFFF

  @file_masks %{
    a: 0x0101010101010101,
    b: 0x0202020202020202,
    c: 0x0404040404040404,
    d: 0x0808080808080808,
    e: 0x1010101010101010,
    f: 0x2020202020202020,
    g: 0x4040404040404040,
    h: 0x8080808080808080
  }

  @spec open_files(Position.t()) :: [atom()]
  def open_files(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> open_files()
  end

  @spec open_files(Bitboard.t()) :: [atom()]
  def open_files(%Bitboard{} = board) do
    pawn_files = Bitwise.bor(board.white_pawns, board.black_pawns)

    Enum.filter(@files, fn file ->
      Bitwise.band(pawn_files, @file_masks[file]) == 0
    end)
  end

  @type material :: %{
          white: %{Chess.Board.piece_type() => non_neg_integer()},
          black: %{Chess.Board.piece_type() => non_neg_integer()}
        }

  @spec material(Position.t()) :: material()
  def material(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> material()
  end

  @spec material(Bitboard.t()) :: material()
  def material(%Bitboard{} = board) do
    %{
      white: material_for_color(board, :white),
      black: material_for_color(board, :black)
    }
  end

  @spec occupied(Position.t()) :: non_neg_integer()
  def occupied(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> occupied()
  end

  @spec occupied(Bitboard.t()) :: non_neg_integer()
  def occupied(%Bitboard{} = board) do
    Bitboard.occupied(board)
  end

  defp material_for_color(board, color) do
    Map.new(@piece_types, fn piece_type ->
      {piece_type, count(board, color, piece_type)}
    end)
  end

  defp count(board, color, piece_type) do
    board
    |> piece_bitboard(color, piece_type)
    |> popcount()
  end

  defp piece_bitboard(board, :white, :pawn), do: board.white_pawns
  defp piece_bitboard(board, :white, :knight), do: board.white_knights
  defp piece_bitboard(board, :white, :bishop), do: board.white_bishops
  defp piece_bitboard(board, :white, :rook), do: board.white_rooks
  defp piece_bitboard(board, :white, :queen), do: board.white_queens
  defp piece_bitboard(board, :white, :king), do: board.white_king

  defp piece_bitboard(board, :black, :pawn), do: board.black_pawns
  defp piece_bitboard(board, :black, :knight), do: board.black_knights
  defp piece_bitboard(board, :black, :bishop), do: board.black_bishops
  defp piece_bitboard(board, :black, :rook), do: board.black_rooks
  defp piece_bitboard(board, :black, :queen), do: board.black_queens
  defp piece_bitboard(board, :black, :king), do: board.black_king

  defp popcount(value), do: popcount(value, 0)

  defp popcount(0, count), do: count

  defp popcount(value, count) do
    popcount(Bitwise.band(value, value - 1), count + 1)
  end

  # --- Square-level facts (board overlays) -----------------------------

  @doc """
  Files with no pawns of `color` but at least one enemy pawn.
  """
  @spec semi_open_files(Position.t()) :: %{white: [atom()], black: [atom()]}
  def semi_open_files(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: semi_open_files_for(board, :white),
      black: semi_open_files_for(board, :black)
    }
  end

  @doc """
  Every square attacked by `color`, including squares occupied by its
  own pieces (a pinned or defended piece still attacks).
  """
  @spec attacked_squares(Position.t()) :: %{white: [0..63], black: [0..63]}
  def attacked_squares(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: attacked_squares(board, :white),
      black: attacked_squares(board, :black)
    }
  end

  @doc """
  Squares of `color`'s pieces that the opponent attacks.
  """
  @spec attacked_pieces(Position.t()) :: %{white: [0..63], black: [0..63]}
  def attacked_pieces(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: attacked_piece_squares(board, :white),
      black: attacked_piece_squares(board, :black)
    }
  end

  @doc """
  The king's square plus its adjacent ring, and which of those squares
  the opponent attacks (measurable king pressure; no vague label).
  """
  @spec king_zone(Position.t(), :white | :black) :: %{
          squares: [0..63],
          attacked: [0..63]
        }
  def king_zone(%Position{} = position, color) when color in [:white, :black] do
    board = Bitboard.from_position(position)
    opponent = opposite(color)

    case king_square(board, color) do
      nil ->
        %{squares: [], attacked: []}

      square ->
        zone = squares_in(Bitwise.bor(Bitwise.bsl(1, square), Bitboard.king_attacks(square)))

        attacked =
          Enum.filter(zone, &Bitboard.attacked?(board, opponent, &1))

        %{squares: zone, attacked: attacked}
    end
  end

  @doc """
  Which kings are attacked. In a legal position only the side to move
  can be in check, but PositionDB also stores hypothetically edited
  positions, so both flags are reported.

  The rule itself lives in `Chess.Position.in_check?/2`; this is the
  position-property view of it for the insights endpoint.
  """
  @spec in_check(Position.t()) :: %{white: boolean(), black: boolean()}
  def in_check(%Position{} = position) do
    %{
      white: Position.in_check?(position, :white),
      black: Position.in_check?(position, :black)
    }
  end

  @doc """
  Outposts for `color`: squares in the opponent's half occupied by a
  knight, not attackable by an enemy pawn, and defended by a friendly
  pawn.
  """
  @spec outposts(Position.t()) :: %{white: [0..63], black: [0..63]}
  def outposts(%Position{} = position) do
    board = Bitboard.from_position(position)

    white_control = pawn_attack_mask_from_pawns(board.white_pawns, :white)
    black_control = pawn_attack_mask_from_pawns(board.black_pawns, :black)

    white_outposts =
      board.white_knights
      |> Bitwise.band(@white_opponent_half)
      |> Bitwise.band(white_control)
      |> Bitwise.band(Bitwise.bnot(black_control))
      |> squares_in()

    black_outposts =
      board.black_knights
      |> Bitwise.band(@black_opponent_half)
      |> Bitwise.band(black_control)
      |> Bitwise.band(Bitwise.bnot(white_control))
      |> squares_in()

    %{white: white_outposts, black: black_outposts}
  end

  @doc """
  Space: squares in the opponent's half attacked by `color`, split into
  all controlled squares and the pawn-controlled subset. The definition
  is intentionally simple and measurable.
  """
  @spec space(Position.t()) :: %{
          white: %{controlled: non_neg_integer(), pawn_space: non_neg_integer()},
          black: %{controlled: non_neg_integer(), pawn_space: non_neg_integer()}
        }
  def space(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: space_for(board, :white),
      black: space_for(board, :black)
    }
  end

  # --- Implementation ---------------------------------------------------

  defp semi_open_files_for(board, color) do
    own_pawns = pawns(board, color)
    enemy_pawns = pawns(board, opposite(color))

    Enum.filter(@files, fn file ->
      Bitwise.band(own_pawns, @file_masks[file]) == 0 and
        Bitwise.band(enemy_pawns, @file_masks[file]) != 0
    end)
  end

  defp pawns(board, :white), do: board.white_pawns
  defp pawns(board, :black), do: board.black_pawns

  defp attacked_squares(board, color) do
    board
    |> Bitboard.pieces()
    |> Enum.filter(fn {_square, {piece_color, _kind}} -> piece_color == color end)
    |> Enum.reduce(0, fn {square, {_color, kind}}, acc ->
      Bitwise.bor(acc, attack_bitboard(board, kind, color, square))
    end)
    |> squares_in()
  end

  defp attack_bitboard(_board, :pawn, color, square), do: Bitboard.pawn_attacks(color, square)

  defp attack_bitboard(_board, :knight, _color, square), do: Bitboard.knight_attacks(square)

  defp attack_bitboard(_board, :king, _color, square), do: Bitboard.king_attacks(square)

  defp attack_bitboard(board, :rook, _color, square), do: Bitboard.rook_attacks(board, square)

  defp attack_bitboard(board, :bishop, _color, square), do: Bitboard.bishop_attacks(board, square)

  defp attack_bitboard(board, :queen, _color, square), do: Bitboard.queen_attacks(board, square)

  defp attacked_piece_squares(board, color) do
    opponent = opposite(color)

    board
    |> Bitboard.pieces()
    |> Enum.filter(fn {_square, {piece_color, _kind}} -> piece_color == color end)
    |> Enum.filter(fn {square, _piece} -> Bitboard.attacked?(board, opponent, square) end)
    |> Enum.map(fn {square, _piece} -> square end)
    |> Enum.sort()
  end

  defp king_square(board, color) do
    board
    |> Bitboard.pieces()
    |> Enum.find_value(fn
      {square, {^color, :king}} -> square
      _ -> nil
    end)
  end

  defp space_for(board, color) do
    controlled =
      board
      |> attacked_squares(color)
      |> Enum.filter(&opponent_half?(color, &1))

    pawn_space =
      board
      |> pawn_attack_mask(color)
      |> squares_in()
      |> Enum.filter(&opponent_half?(color, &1))

    %{controlled: length(controlled), pawn_space: length(pawn_space)}
  end

  defp pawn_attack_mask_from_pawns(pawns, :white) do
    left = Bitwise.bsl(Bitwise.band(pawns, @not_a_file), 7)
    right = Bitwise.bsl(Bitwise.band(pawns, @not_h_file), 9)

    Bitwise.band(Bitwise.bor(left, right), @board_mask)
  end

  defp pawn_attack_mask_from_pawns(pawns, :black) do
    left = Bitwise.bsr(Bitwise.band(pawns, @not_a_file), 9)
    right = Bitwise.bsr(Bitwise.band(pawns, @not_h_file), 7)

    Bitwise.bor(left, right)
  end

  defp pawn_attack_mask(board, color) do
    board
    |> Bitboard.pieces()
    |> Enum.filter(fn {_square, piece} -> piece == {color, :pawn} end)
    |> Enum.reduce(0, fn {square, _piece}, acc ->
      Bitwise.bor(acc, Bitboard.pawn_attacks(color, square))
    end)
  end

  defp opponent_half?(:white, square), do: square >= 32
  defp opponent_half?(:black, square), do: square <= 31

  defp attacked_by?(mask, square) do
    Bitwise.band(mask, Bitwise.bsl(1, square)) != 0
  end

  defp opposite(:white), do: :black
  defp opposite(:black), do: :white

  defp squares_in(mask) do
    for square <- 0..63, attacked_by?(mask, square), do: square
  end
end
