defmodule Features.Catalogue.TacticMap do
  @moduledoc """
  Tactical geometry and move analysis shared by sections 12-14: pins,
  skewers, forks, discovered attacks, defenders, forcing moves and
  piece-alignment rays. All relations are heuristics pinned by tests.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support}
  alias Features.Chess.{AttackTables, Bitboard, Board, Square}

  @dirs_straight [{0, 1}, {0, -1}, {1, 0}, {-1, 0}]
  @dirs_diagonal [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

  @doc "Pseudo-legal moves of `color`."
  @spec pseudo_moves(Board.t(), atom()) :: [Features.Chess.Move.t()]
  def pseudo_moves(board, color), do: MobilityMap.pseudo_moves(board, color)

  @doc "Pseudo-legal capturing moves of `color`."
  @spec captures(Board.t(), atom()) :: [Features.Chess.Move.t()]
  def captures(board, color) do
    enemy = enemy_piece_bb(board, color)

    board
    |> pseudo_moves(color)
    |> Enum.filter(&((1 <<< &1.to &&& enemy) != 0))
  end

  @doc "Pseudo-legal moves of `color` that give check."
  @spec checks(Board.t(), atom()) :: [Features.Chess.Move.t()]
  def checks(board, color) do
    king = enemy_king_square(board, color)

    if king == nil do
      []
    else
      board
      |> pseudo_moves(color)
      |> Enum.filter(fn move ->
        after_board = Board.apply_move(board, move)
        Board.attacked?(after_board, king, color)
      end)
    end
  end

  @doc "Moves of `color` that give check or capture."
  @spec forcing(Board.t(), atom()) :: [Features.Chess.Move.t()]
  def forcing(board, color) do
    captures = MapSet.new(captures(board, color), &move_key/1)
    checks = MapSet.new(checks(board, color), &move_key/1)

    board
    |> pseudo_moves(color)
    |> Enum.filter(&MapSet.member?(MapSet.union(captures, checks), move_key(&1)))
  end

  @doc "Pieces of `color` attacking at least two enemy pieces."
  @spec multi_attackers(Board.t(), atom(), [atom()]) :: [non_neg_integer()]
  def multi_attackers(board, color, types) do
    enemy = enemy_piece_bb(board, color)

    for type <- types,
        square <- Bitboard.squares(Board.piece_bb(board, color, type)),
        Support.popcount(piece_attacks(board, color, type, square) &&& enemy) >= 2,
        do: square
  end

  @doc "Pinned pieces of `color`: %{square => :absolute | :relative}."
  @spec pins(Board.t(), atom()) :: %{non_neg_integer() => atom()}
  def pins(board, color) do
    enemy = Board.opposite(color)

    sliders(board, enemy)
    |> Enum.flat_map(fn {type, square} ->
      Enum.map(ray_dirs(type), &blockers_on(board, square, &1))
    end)
    |> Enum.reduce(%{}, fn blockers, pins ->
      case blockers do
        [{sq, {^color, type}}, {_ksq, {^color, :kings}}] when type != :kings ->
          Map.put(pins, sq, :absolute)

        [{sq, {^color, type}}, {_sq2, {^color, _t2}}] when type != :kings ->
          Map.put(pins, sq, :relative)

        _ ->
          pins
      end
    end)
  end

  @doc "Front squares of `color` pieces that are skewered by enemy sliders."
  @spec skewers(Board.t(), atom()) :: [non_neg_integer()]
  def skewers(board, color) do
    enemy = Board.opposite(color)

    sliders(board, enemy)
    |> Enum.flat_map(fn {type, square} ->
      Enum.map(ray_dirs(type), &blockers_on(board, square, &1))
    end)
    |> Enum.flat_map(fn blockers ->
      case blockers do
        [{_sq, {^color, :kings}} | _] ->
          []

        [{sq, {^color, _type}}, {_sq2, {^color, _t2}}] ->
          [sq]

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  @doc "Discovered relations for `color`: %{discoverer_square => %{target: sq, king: bool}}."
  @spec discoveries(Board.t(), atom()) :: %{non_neg_integer() => map()}
  def discoveries(board, color) do
    enemy = Board.opposite(color)

    board
    |> own_sliders(color)
    |> Enum.flat_map(fn {type, square} ->
      Enum.map(ray_dirs(type), &blockers_on(board, square, &1))
    end)
    |> Enum.flat_map(fn blockers ->
      case blockers do
        [{disc, {^color, _type}}, {target, {^enemy, target_type}}] ->
          [{disc, %{target: target, king: target_type == :kings}}]

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  @doc "Own pieces of `color` that are overloaded defenders."
  @spec overloaded(Board.t(), atom()) :: [non_neg_integer()]
  def overloaded(board, color) do
    own = Board.color_occupancy(board, color)
    enemy_attacks = AttackMap.attack_counts(board, Board.opposite(color))

    pieces(board, color)
    |> Enum.filter(fn {type, square} ->
      defended =
        (piece_attacks(board, color, type, square) &&& own &&& bnot(1 <<< square))
        |> Support.popcount()

      defended >= 2 and Map.get(enemy_attacks, square, 0) >= 1
    end)
    |> Enum.map(fn {_type, square} -> square end)
    |> Enum.sort()
  end

  @doc "Pieces of `color` that defend something and are themselves attacked."
  @spec deflection_squares(Board.t(), atom()) :: [non_neg_integer()]
  def deflection_squares(board, color) do
    enemy = Board.opposite(color)
    our_attacks = AttackMap.attack_counts(board, color)

    board
    |> defenders_map(enemy)
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(our_attacks, &1))
    |> Enum.sort()
  end

  @doc "Enemy pieces that are the sole defender of another enemy piece and are attacked."
  @spec sole_defenders(Board.t(), atom()) :: [non_neg_integer()]
  def sole_defenders(board, color) do
    enemy = Board.opposite(color)
    our_attacks = AttackMap.attack_counts(board, color)

    board
    |> defenders_map(enemy)
    |> Enum.filter(fn {_target, defenders} -> length(defenders) == 1 end)
    |> Enum.map(fn {_target, [defender]} -> defender end)
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(our_attacks, &1))
    |> Enum.sort()
  end

  @doc "Enemy pieces that defend their own king's ring."
  @spec decoy_squares(Board.t(), atom()) :: [non_neg_integer()]
  def decoy_squares(board, color) do
    enemy = Board.opposite(color)
    ring = king_ring_bb(board, enemy)
    king = Board.piece_bb(board, enemy, :kings)

    (AttackMap.attackers_into(board, enemy, ring) &&& bnot(king))
    |> Bitboard.squares()
    |> Enum.sort()
  end

  @doc "Empty squares between two aligned enemy pieces (interference points)."
  @spec interference_squares(Board.t(), atom()) :: [non_neg_integer()]
  def interference_squares(board, color) do
    enemy_pieces = pieces(board, Board.opposite(color))

    enemy_pieces
    |> each_pair()
    |> Enum.flat_map(fn {{t1, a}, {t2, b}} ->
      if aligned_pieces?({t1, a}, {t2, b}) do
        between_squares(a, b)
      else
        []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Own pieces lying strictly between two aligned own pieces (clearance pieces)."
  @spec clearance_squares(Board.t(), atom()) :: [non_neg_integer()]
  def clearance_squares(board, color) do
    own_pieces = pieces(board, color)

    own_pieces
    |> each_pair()
    |> Enum.flat_map(fn {{t1, a}, {t2, b}} ->
      if aligned_pieces?({t1, a}, {t2, b}) do
        between_squares(a, b) |> Enum.filter(&occupied?(board, &1))
      else
        []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Aligned, clear slider pairs of `color` that form a battery."
  @spec battery_sliders(Board.t(), atom()) :: [{non_neg_integer(), non_neg_integer()}]
  def battery_sliders(board, color) do
    board
    |> sliders(color)
    |> each_pair()
    |> Enum.flat_map(fn {{t1, a}, {t2, b}} ->
      if aligned_pieces?({t1, a}, {t2, b}) and clear_between?(board, a, b),
        do: [{a, b}],
        else: []
    end)
  end

  @doc "Whether `color` has any clear aligned slider battery."
  @spec battery?(Board.t(), atom()) :: boolean()
  def battery?(board, color), do: battery_sliders(board, color) != []

  @doc "Whether `color` has both a forcing move and a quiet move."
  @spec zwischenzug?(Board.t(), atom()) :: boolean()
  def zwischenzug?(board, color) do
    forcing_set = MapSet.new(forcing(board, color), &move_key/1)

    quiet =
      board
      |> pseudo_moves(color)
      |> Enum.any?(&(not MapSet.member?(forcing_set, move_key(&1))))

    MapSet.size(forcing_set) > 0 and quiet
  end

  @doc "Own non-king pieces of `color` without any pseudo-legal move."
  @spec trapped_squares(Board.t(), atom()) :: [non_neg_integer()]
  def trapped_squares(board, color) do
    counts = MobilityMap.piece_counts(board, color)

    board
    |> pieces_squares(color)
    |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))
    |> Enum.reject(&Map.has_key?(counts, &1))
    |> Enum.sort()
  end

  @doc "Own pieces of `color` that are attacked and undefended."
  @spec loose_squares(Board.t(), atom()) :: [non_neg_integer()]
  def loose_squares(board, color) do
    defenders = AttackMap.defender_counts(board, color)
    attackers = AttackMap.attack_counts(board, Board.opposite(color))

    pieces_squares(board, color)
    |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))
    |> Enum.filter(&(not Map.has_key?(defenders, &1) and Map.has_key?(attackers, &1)))
    |> Enum.sort()
  end

  @doc "Own pieces of `color` that are attacked twice and undefended."
  @spec hanging_squares(Board.t(), atom()) :: [non_neg_integer()]
  def hanging_squares(board, color) do
    defenders = AttackMap.defender_counts(board, color)
    attackers = AttackMap.attack_counts(board, Board.opposite(color))

    pieces_squares(board, color)
    |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))
    |> Enum.filter(&(not Map.has_key?(defenders, &1) and Map.get(attackers, &1, 0) >= 2))
    |> Enum.sort()
  end

  @doc "Square attacked from the moved piece's new home, for threats analysis."
  @spec post_move_attack(Board.t(), Features.Chess.Move.t(), atom()) :: non_neg_integer()
  def post_move_attack(board, move, color) do
    after_board = Board.apply_move(board, move)

    case Board.piece_at(after_board, move.to) do
      {^color, type} -> piece_attacks(after_board, color, type, move.to)
      _ -> 0
    end
  end

  @doc "Attack bitboard of a piece."
  @spec piece_attacks(Board.t(), atom(), atom(), non_neg_integer()) :: non_neg_integer()
  def piece_attacks(_board, color, :pawns, square) do
    if color == :white, do: AttackTables.white_pawn(square), else: AttackTables.black_pawn(square)
  end

  def piece_attacks(_board, _color, :knights, square), do: AttackTables.knight(square)
  def piece_attacks(_board, _color, :kings, square), do: AttackTables.king(square)

  def piece_attacks(board, _color, :bishops, square),
    do: AttackTables.bishop_attacks(square, Board.occupancy(board))

  def piece_attacks(board, _color, :rooks, square),
    do: AttackTables.rook_attacks(square, Board.occupancy(board))

  def piece_attacks(board, _color, :queens, square),
    do: AttackTables.queen_attacks(square, Board.occupancy(board))

  @doc "Square of `color`'s king."
  @spec king_square(Board.t(), atom()) :: non_neg_integer() | nil
  def king_square(board, color) do
    board
    |> Board.piece_bb(color, :kings)
    |> Bitboard.squares()
    |> List.first()
  end

  @doc "Square of the enemy king relative to `color`."
  @spec enemy_king_square(Board.t(), atom()) :: non_neg_integer() | nil
  def enemy_king_square(board, color), do: king_square(board, Board.opposite(color))

  @doc "3x3 ring around `color`'s king, without the king square."
  @spec king_ring_bb(Board.t(), atom()) :: non_neg_integer()
  def king_ring_bb(board, color) do
    case king_square(board, color) do
      nil ->
        0

      king ->
        file = Square.file(king)
        rank = Square.rank(king)

        for(
          f <- (file - 1)..(file + 1),
          r <- (rank - 1)..(rank + 1),
          f in 0..7,
          r in 0..7,
          f != file or r != rank,
          do: r * 8 + f
        )
        |> Enum.reduce(0, fn square, bits -> bits ||| 1 <<< square end)
    end
  end

  @doc "All pieces of `color` as {type, square} pairs."
  @spec pieces(Board.t(), atom()) :: [{atom(), non_neg_integer()}]
  def pieces(board, color) do
    for type <- Board.types(),
        square <- Bitboard.squares(Board.piece_bb(board, color, type)),
        do: {type, square}
  end

  @doc "Squares occupied by `color`."
  @spec pieces_squares(Board.t(), atom()) :: [non_neg_integer()]
  def pieces_squares(board, color) do
    board
    |> Board.color_occupancy(color)
    |> Bitboard.squares()
    |> Enum.sort()
  end

  @doc "All enemy non-king occupied squares."
  @spec enemy_piece_bb(Board.t(), atom()) :: non_neg_integer()
  def enemy_piece_bb(board, color) do
    enemy = Board.opposite(color)
    Board.color_occupancy(board, enemy) &&& bnot(Board.piece_bb(board, enemy, :kings))
  end

  @doc "Squares of `color`'s enemy pieces that the moved piece attacks after move."
  def threatens?(board, move, color) do
    (post_move_attack(board, move, color) &&& enemy_piece_bb(board, color)) != 0
  end

  defp defenders_map(board, color) do
    pieces(board, color)
    |> Enum.reduce(%{}, fn {type, square}, defenders ->
      piece_attacks(board, color, type, square)
      |> Bitboard.squares()
      |> Enum.reduce(defenders, fn target, defenders ->
        Map.update(defenders, target, [square], &[square | &1])
      end)
    end)
  end

  defp sliders(board, color) do
    for type <- [:rooks, :bishops, :queens],
        square <- Bitboard.squares(Board.piece_bb(board, color, type)),
        do: {type, square}
  end

  defp own_sliders(board, color), do: sliders(board, color)

  defp ray_dirs(:rooks), do: @dirs_straight
  defp ray_dirs(:bishops), do: @dirs_diagonal
  defp ray_dirs(:queens), do: @dirs_straight ++ @dirs_diagonal
  defp ray_dirs(_other), do: []

  defp blockers_on(board, square, {df, dr}) do
    square
    |> ray(df, dr)
    |> Enum.reduce([], fn sq, acc ->
      case Board.piece_at(board, sq) do
        nil -> acc
        piece -> [{sq, piece} | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.take(2)
  end

  defp ray(square, df, dr) do
    file = Square.file(square) + df
    rank = Square.rank(square) + dr

    if file in 0..7 and rank in 0..7 do
      next = rank * 8 + file
      [next | ray(next, df, dr)]
    else
      []
    end
  end

  defp aligned_pieces?({t1, a}, {t2, b}) do
    straight = t1 in [:rooks, :queens] and t2 in [:rooks, :queens]
    diagonal = t1 in [:bishops, :queens] and t2 in [:bishops, :queens]

    (straight and
       (Square.file(a) == Square.file(b) or Square.rank(a) == Square.rank(b))) or
      (diagonal and
         abs(Square.file(a) - Square.file(b)) == abs(Square.rank(a) - Square.rank(b)))
  end

  defp between_squares(a, b) do
    step = step_size(a, b)

    (a + step)..b//step
    |> Enum.to_list()
    |> Enum.reject(&(&1 == b))
  end

  defp step_size(a, b) do
    df = sign(Square.file(b) - Square.file(a))
    dr = sign(Square.rank(b) - Square.rank(a))
    df + 8 * dr
  end

  defp sign(value) when value > 0, do: 1
  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 0

  defp each_pair(pieces) do
    for {first, index} <- Enum.with_index(pieces),
        {second, other_index} <- Enum.with_index(pieces),
        index < other_index,
        do: {first, second}
  end

  defp clear_between?(board, a, b) do
    a
    |> between_squares(b)
    |> Enum.all?(&(Board.piece_at(board, &1) == nil))
  end

  defp occupied?(board, square), do: Board.piece_at(board, square) != nil

  defp move_key(move), do: {move.from, move.to, move.promotion}
end
