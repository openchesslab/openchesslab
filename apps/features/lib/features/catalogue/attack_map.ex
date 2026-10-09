defmodule Features.Catalogue.AttackMap do
  @moduledoc """
  Shared attack analysis: per-square attacker counts and attacked-square
  bitboards for either colour, used by the placement, center, squares,
  lines, attacks and king sections.
  """

  import Bitwise

  alias Features.Chess.{AttackTables, Bitboard, Board}

  @type counts :: %{non_neg_integer() => pos_integer()}
  @type cached :: %{atom() => {counts(), non_neg_integer()}}

  @doc """
  Precompute per-square attacker counts and the attacked bitboard for
  both colours in a single pass. Attach the result to the board's
  `attack_table` field (see `Features.extract/2`); the readers below use
  it automatically and fall back to computing on demand otherwise.
  """
  @spec build(Board.t()) :: cached()
  def build(board) do
    Map.new(Board.colors(), fn color -> {color, scan(board, color)} end)
  end

  @doc """
  Number of pieces of `color` attacking each square; squares with no
  attacker are omitted.
  """
  @spec attack_counts(Board.t(), atom()) :: counts()
  def attack_counts(%Board{attack_table: table}, color) when is_map(table),
    do: elem(Map.fetch!(table, color), 0)

  def attack_counts(board, color), do: elem(scan(board, color), 0)

  @doc "Attacker counts of `color` restricted to squares occupied by `color`."
  @spec defender_counts(Board.t(), atom()) :: counts()
  def defender_counts(board, color) do
    own = Board.color_occupancy(board, color)

    board
    |> attack_counts(color)
    |> Map.filter(fn {square, _count} -> (1 <<< square &&& own) != 0 end)
  end

  @doc "Bitboard of all squares attacked by `color`."
  @spec attacked_bb(Board.t(), atom()) :: non_neg_integer()
  def attacked_bb(%Board{attack_table: table}, color) when is_map(table),
    do: elem(Map.fetch!(table, color), 1)

  def attacked_bb(board, color) do
    occupancy = Board.occupancy(board)

    Enum.reduce(Board.types(), 0, fn type, union ->
      board
      |> Board.piece_bb(color, type)
      |> Bitboard.squares()
      |> Enum.reduce(union, fn square, union ->
        union ||| attack_bits(color, type, square, occupancy)
      end)
    end)
  end

  @doc "How many pieces of `color` attack `square`."
  @spec attackers(Board.t(), non_neg_integer(), atom()) :: non_neg_integer()
  def attackers(board, square, color) do
    Map.get(attack_counts(board, color), square, 0)
  end

  @doc "Bitboard of pieces of `color` that attack at least one square of `targets`."
  @spec attackers_into(Board.t(), atom(), non_neg_integer()) :: non_neg_integer()
  def attackers_into(board, color, targets) do
    occupancy = Board.occupancy(board)

    Enum.reduce(Board.types(), 0, fn type, attackers ->
      board
      |> Board.piece_bb(color, type)
      |> Bitboard.squares()
      |> Enum.reduce(attackers, fn square, attackers ->
        if (attack_bits(color, type, square, occupancy) &&& targets) == 0,
          do: attackers,
          else: attackers ||| 1 <<< square
      end)
    end)
  end

  defp scan(board, color) do
    occupancy = Board.occupancy(board)

    {counts, union} =
      Enum.reduce(Board.types(), {%{}, 0}, fn type, {counts, union} ->
        board
        |> Board.piece_bb(color, type)
        |> Bitboard.squares()
        |> Enum.reduce({counts, union}, fn square, {counts, union} ->
          bits = attack_bits(color, type, square, occupancy)
          union = union ||| bits

          counts =
            Enum.reduce(Bitboard.squares(bits), counts, fn target, counts ->
              Map.update(counts, target, 1, &(&1 + 1))
            end)

          {counts, union}
        end)
      end)

    {counts, union}
  end

  defp attack_bits(color, :pawns, square, _occupancy) do
    if color == :white,
      do: AttackTables.white_pawn(square),
      else: AttackTables.black_pawn(square)
  end

  defp attack_bits(_color, :knights, square, _occupancy), do: AttackTables.knight(square)
  defp attack_bits(_color, :kings, square, _occupancy), do: AttackTables.king(square)

  defp attack_bits(_color, :bishops, square, occupancy),
    do: AttackTables.bishop_attacks(square, occupancy)

  defp attack_bits(_color, :rooks, square, occupancy),
    do: AttackTables.rook_attacks(square, occupancy)

  defp attack_bits(_color, :queens, square, occupancy),
    do: AttackTables.queen_attacks(square, occupancy)
end
