defmodule Features.Catalogue.Threats do
  @moduledoc """
  Spec section 13 — concrete tactical threats: checks, capture threats,
  mate threats, forks, pins, sacrifices and forcing-move density.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("threats.check", 13, [{13, "check"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)

          AttackMap.attack_counts(board, enemy)
          |> Map.get(TacticMap.king_square(board, color), 0) >= 1
        end)
      end),
      Feature.new("threats.aantal_checks", 13, [{13, "aantal checks"}], fn board ->
        per_color(board, fn board, color -> length(TacticMap.checks(board, color)) end)
      end),
      Feature.new("threats.capture_threats", 13, [{13, "capture threats"}], fn board ->
        per_color(board, fn board, color -> length(TacticMap.captures(board, color)) end)
      end),
      Feature.new("threats.mate_threat", 13, [{13, "mate threat"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.checks(board, color) != [] and
            length(escape_squares(board, Board.opposite(color))) <= 1
        end)
      end),
      Feature.new("threats.mating_net", 13, [{13, "mating net"}], fn board ->
        per_color(board, fn board, color ->
          ring_attack_count(board, color) >= 3 and
            length(escape_squares(board, Board.opposite(color))) <= 1
        end)
      end),
      Feature.new("threats.promotion_threat", 13, [{13, "promotion threat"}], fn board ->
        per_color(board, fn board, color -> promotion_threats(board, color) |> to_alg() end)
      end),
      Feature.new(
        "threats.discovered_attack_threat",
        13,
        [{13, "discovered attack threat"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> TacticMap.discoveries(color)
            |> Enum.filter(fn {_disc, info} ->
              case Board.piece_at(board, info.target) do
                {_color, type} -> Support.value(type) >= 5
                nil -> false
              end
            end)
            |> Enum.map(fn {disc, _info} -> disc end)
            |> Enum.sort()
            |> to_alg()
          end)
        end
      ),
      Feature.new("threats.fork_threat", 13, [{13, "fork threat"}], fn board ->
        per_color(board, fn board, color -> fork_threat_squares(board, color) |> to_alg() end)
      end),
      Feature.new("threats.pin_exploitation", 13, [{13, "pin exploitation"}], fn board ->
        per_color(board, fn board, color -> pinned_enemy(board, color) |> to_alg() end)
      end),
      Feature.new(
        "threats.sacrifice_opportunity",
        13,
        [{13, "sacrifice opportunity"}],
        fn board ->
          per_color(board, fn board, color -> sacrifice_squares(board, color) |> to_alg() end)
        end
      ),
      Feature.new("threats.tactical_tension", 13, [{13, "tactical tension"}], fn board ->
        tension(board)
      end),
      Feature.new("threats.forcing_move_density", 13, [{13, "forcing-move density"}], fn board ->
        per_color(board, fn board, color ->
          total = length(TacticMap.pseudo_moves(board, color))

          if total != 0 do
            density = length(TacticMap.forcing(board, color)) / total
            Float.round(density, 2)
          end
        end)
      end),
      Feature.new("threats.aantal_forcing_moves", 13, [{13, "aantal forcing moves"}], fn board ->
        per_color(board, fn board, color -> length(TacticMap.forcing(board, color)) end)
      end),
      Feature.new(
        "threats.check_capture_threat_moves",
        13,
        [{13, "check/capture/threat-mogelijkheden"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> TacticMap.pseudo_moves(color)
            |> Enum.count(&check_capture_threat?(board, &1, color))
          end)
        end
      )
    ]
  end

  defp fork_threat_squares(board, color) do
    enemy_occ = Board.color_occupancy(board, Board.opposite(color))

    for type <- [:pawns, :knights, :bishops],
        square <- Bitboard.squares(Board.piece_bb(board, color, type)),
        targets =
          Bitboard.squares(TacticMap.piece_attacks(board, color, type, square) &&& enemy_occ),
        length(targets) >= 2,
        Enum.any?(targets, &valuable_target?(board, &1)),
        do: square
  end

  defp sacrifice_squares(board, color) do
    enemy = Board.opposite(color)
    enemy_majors = Board.piece_bb(board, enemy, :rooks) ||| Board.piece_bb(board, enemy, :queens)
    defenders = AttackMap.defender_counts(board, enemy)

    for(
      type <- [:pawns, :knights, :bishops],
      square <- Bitboard.squares(Board.piece_bb(board, color, type)),
      target <-
        Bitboard.squares(TacticMap.piece_attacks(board, color, type, square) &&& enemy_majors),
      Map.has_key?(defenders, target),
      do: target
    )
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp pinned_enemy(board, color) do
    board
    |> TacticMap.pins(Board.opposite(color))
    |> Enum.filter(fn {_square, kind} -> kind == :absolute end)
    |> Enum.map(fn {square, _kind} -> square end)
    |> Enum.sort()
  end

  defp promotion_threats(board, color) do
    target_rank = if color == :white, do: 6, else: 1

    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.filter(&(Square.rank(&1) == target_rank))
    |> Enum.sort()
  end

  defp escape_squares(board, color) do
    king = TacticMap.king_square(board, color)

    if king == nil do
      []
    else
      attacked = AttackMap.attack_counts(board, Board.opposite(color))

      board
      |> TacticMap.pseudo_moves(color)
      |> Enum.filter(&(&1.from == king))
      |> Enum.map(& &1.to)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(attacked, &1))
      |> Enum.sort()
    end
  end

  defp ring_attack_count(board, color) do
    ring = TacticMap.king_ring_bb(board, Board.opposite(color))
    counts = AttackMap.attack_counts(board, color)

    ring
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
  end

  defp tension(board) do
    white = board |> AttackMap.attack_counts(:white) |> Map.keys()
    black = board |> AttackMap.attack_counts(:black) |> Map.keys()

    white
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(black))
    |> MapSet.size()
  end

  defp check_capture_threat?(board, move, color) do
    enemy_bb = TacticMap.enemy_piece_bb(board, color)
    threatens_bb = TacticMap.post_move_attack(board, move, color) &&& enemy_bb

    captures = 1 <<< move.to &&& enemy_bb
    checks = MapSet.new(TacticMap.checks(board, color), &move_key/1)

    captures != 0 or threatens_bb != 0 or MapSet.member?(checks, move_key(move))
  end

  defp valuable_target?(board, square) do
    case Board.piece_at(board, square) do
      {_color, :kings} -> true
      {_color, type} -> Support.value(type) >= 5
      nil -> false
    end
  end

  defp move_key(move), do: {move.from, move.to, move.promotion}

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
