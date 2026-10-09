defmodule Features.Catalogue.AttackMap do
  @moduledoc """
  Shared attack analysis: per-square attacker counts and attacked-square
  bitboards for either colour, used by the placement, center, squares,
  lines, attacks and king sections.
  """

  import Bitwise

  alias Features.Chess.{AttackTables, Bitboard, Board}

  @type counts :: %{non_neg_integer() => pos_integer()}

  @doc """
  Number of pieces of `color` attacking each square; squares with no
  attacker are omitted.
  """
  @spec attack_counts(Board.t(), atom()) :: counts()
  def attack_counts(board, color) do
    occupancy = Board.occupancy(board)

    targets =
      for type <- Board.types(),
          square <- Bitboard.squares(Board.piece_bb(board, color, type)),
          do: attack_bits(color, type, square, occupancy)

    Enum.reduce(targets, %{}, fn bitboard, counts ->
      Enum.reduce(Bitboard.squares(bitboard), counts, fn square, counts ->
        Map.update(counts, square, 1, &(&1 + 1))
      end)
    end)
  end

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
