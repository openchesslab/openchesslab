defmodule Features.Catalogue.Motifs do
  @moduledoc """
  Spec section 14 — specific tactical motifs: Greek gift, back-rank and
  smothered mate, sacrifices, trapped queens, mating batteries, f2/f7.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("motifs.greek_gift", 14, [{14, "Greek gift / Bxh7+ of ...Bxh2+"}], fn board ->
        per_color(board, fn board, color -> greek_gift?(board, color) end)
      end),
      Feature.new("motifs.back_rank_motifs", 14, [{14, "back-rank motifs"}], fn board ->
        per_color(board, fn board, color -> back_rank_motif?(board, color) end)
      end),
      Feature.new("motifs.smothered_mate_motifs", 14, [{14, "smothered-mate motifs"}], fn board ->
        per_color(board, fn board, color -> smothered_mate?(board, color) end)
      end),
      Feature.new(
        "motifs.rook_sacrifice_against_king",
        14,
        [{14, "rook sacrifice against king"}],
        fn board ->
          per_color(board, fn board, color -> rook_sacrifice?(board, color) end)
        end
      ),
      Feature.new("motifs.exchange_sacrifice", 14, [{14, "exchange sacrifice"}], fn board ->
        per_color(board, fn board, color -> exchange_sacrifices(board, color) |> to_alg() end)
      end),
      Feature.new("motifs.clearance_sacrifice", 14, [{14, "clearance sacrifice"}], fn board ->
        per_color(board, fn board, color -> clearance_sacrifice?(board, color) end)
      end),
      Feature.new("motifs.deflection", 14, [{14, "deflection"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.deflection_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new("motifs.overloaded_defender", 14, [{14, "overloaded defender"}], fn board ->
        per_color(board, fn board, color -> TacticMap.overloaded(board, color) |> to_alg() end)
      end),
      Feature.new("motifs.trapped_queen", 14, [{14, "trapped queen"}], fn board ->
        per_color(board, fn board, color -> trapped_queens(board, color) |> to_alg() end)
      end),
      Feature.new("motifs.mating_battery", 14, [{14, "mating battery"}], fn board ->
        per_color(board, fn board, color -> mating_battery?(board, color) end)
      end),
      Feature.new("motifs.f2_f7_attack", 14, [{14, "f2/f7 attack"}], fn board ->
        per_color(board, fn board, color ->
          target = if color == :white, do: 53, else: 13
          Map.get(AttackMap.attack_counts(board, color), target, 0)
        end)
      end)
    ]
  end

  defp greek_gift?(board, color) do
    h_square = if color == :white, do: 55, else: 15

    case TacticMap.king_square(board, Board.opposite(color)) do
      nil ->
        false

      king ->
        g_file? = Square.file(king) == 6
        pawn? = Board.piece_at(board, h_square) == {Board.opposite(color), :pawns}
        bishop_attacks_h? = bishop_attacks_h?(board, color, h_square)
        g_file? and pawn? and bishop_attacks_h?
    end
  end

  defp back_rank_motif?(board, color) do
    enemy = Board.opposite(color)
    back = if enemy == :white, do: 0, else: 7

    case TacticMap.king_square(board, enemy) do
      nil ->
        false

      king ->
        Square.rank(king) == back and front_blocked_by_own?(board, enemy, king)
    end
  end

  defp smothered_mate?(board, color) do
    enemy = Board.opposite(color)

    case TacticMap.king_square(board, enemy) do
      nil ->
        false

      king ->
        back = if enemy == :white, do: 0, else: 7
        on_back_edge? = Square.rank(king) == back
        corner_file? = Square.file(king) in [6, 7]
        ring = TacticMap.king_ring_bb(board, enemy)

        knight_forks_ring? =
          board
          |> Board.piece_bb(color, :knights)
          |> Bitboard.squares()
          |> Enum.any?(fn square ->
            (TacticMap.piece_attacks(board, color, :knights, square) &&& ring) != 0
          end)

        on_back_edge? and corner_file? and knight_forks_ring?
    end
  end

  defp rook_sacrifice?(board, color) do
    enemy = Board.opposite(color)
    h_square = if color == :white, do: 55, else: 15

    case TacticMap.king_square(board, enemy) do
      nil ->
        false

      king ->
        Square.file(king) == 6 and
          Board.piece_at(board, h_square) == {enemy, :pawns} and
          rook_attacks_square?(board, color, h_square)
    end
  end

  defp exchange_sacrifices(board, color) do
    enemy = Board.opposite(color)

    enemy_minors =
      Board.piece_bb(board, enemy, :bishops) ||| Board.piece_bb(board, enemy, :knights)

    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.flat_map(fn square ->
      (TacticMap.piece_attacks(board, color, :rooks, square) &&& enemy_minors)
      |> Bitboard.squares()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp clearance_sacrifice?(board, color) do
    board
    |> TacticMap.discoveries(color)
    |> Enum.any?(fn {disc, info} ->
      info.king and Board.piece_at(board, disc) == {color, :pawns}
    end)
  end

  defp trapped_queens(board, color) do
    enemy = Board.opposite(color)
    counts = MobilityMap.piece_counts(board, enemy)

    board
    |> Board.piece_bb(enemy, :queens)
    |> Bitboard.squares()
    |> Enum.filter(&(Map.get(counts, &1, 0) <= 1))
    |> Enum.sort()
  end

  defp mating_battery?(board, color) do
    enemy = Board.opposite(color)
    targets = TacticMap.king_ring_bb(board, enemy) ||| Board.piece_bb(board, enemy, :kings)

    board
    |> TacticMap.battery_sliders(color)
    |> Enum.any?(fn {a, b} ->
      case {Board.piece_at(board, a), Board.piece_at(board, b)} do
        {{^color, :queens}, {^color, :rooks}} ->
          attacks =
            TacticMap.piece_attacks(board, color, :queens, a) |||
              TacticMap.piece_attacks(board, color, :rooks, b)

          (attacks &&& targets) != 0

        {{^color, :rooks}, {^color, :queens}} ->
          attacks =
            TacticMap.piece_attacks(board, color, :queens, b) |||
              TacticMap.piece_attacks(board, color, :rooks, a)

          (attacks &&& targets) != 0

        _ ->
          false
      end
    end)
  end

  defp bishop_attacks_h?(board, color, h_square) do
    board
    |> Board.piece_bb(color, :bishops)
    |> Bitboard.squares()
    |> Enum.any?(fn square ->
      (TacticMap.piece_attacks(board, color, :bishops, square) &&& 1 <<< h_square) != 0
    end)
  end

  defp rook_attacks_square?(board, color, square) do
    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.any?(fn s ->
      (TacticMap.piece_attacks(board, color, :rooks, s) &&& 1 <<< square) != 0
    end)
  end

  defp front_blocked_by_own?(board, color, king) do
    file = Square.file(king)
    rank = if color == :white, do: 1, else: 6
    front = rank * 8 + file

    case Board.piece_at(board, front) do
      {^color, :pawns} -> true
      _ -> false
    end
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
