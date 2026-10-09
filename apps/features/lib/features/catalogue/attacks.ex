defmodule Features.Catalogue.Attacks do
  @moduledoc """
  Spec section 10 — attack and defence relationships.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support}
  alias Features.Chess.{AttackTables, Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("attacks.map", 10, [{10, "attack map"}], fn board ->
        per_color(board, fn board, color -> attacked_squares(board, color) end)
      end),
      Feature.new("attacks.attacked_squares", 10, [{10, "attacked squares"}], fn board ->
        union = AttackMap.attacked_bb(board, :white) ||| AttackMap.attacked_bb(board, :black)
        union |> Bitboard.squares() |> to_alg()
      end),
      Feature.new("attacks.defended_squares", 10, [{10, "defended squares"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> AttackMap.defender_counts(color)
          |> Map.keys()
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new(
        "attacks.attackers_per_square",
        10,
        [{10, "aantal aanvallers per veld"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> AttackMap.attack_counts(color)
            |> Map.new(fn {square, count} -> {Square.to_string(square), count} end)
          end)
        end
      ),
      Feature.new(
        "attacks.defenders_per_square",
        10,
        [{10, "aantal verdedigers per veld"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> AttackMap.defender_counts(color)
            |> Map.new(fn {square, count} -> {Square.to_string(square), count} end)
          end)
        end
      ),
      Feature.new("attacks.attacked_pieces", 10, [{10, "attacked pieces"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.color_occupancy(board, Board.opposite(color))

          board
          |> AttackMap.attack_counts(color)
          |> Map.keys()
          |> Enum.filter(&((1 <<< &1 &&& enemy) != 0))
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("attacks.undefended", 10, [{10, "undefended pieces"}], fn board ->
        per_color(board, fn board, color ->
          defenders = AttackMap.defender_counts(board, color)

          own_non_king(board, color)
          |> Enum.filter(&(not Map.has_key?(defenders, &1)))
          |> to_alg()
        end)
      end),
      Feature.new("attacks.loose", 10, [{10, "loose pieces"}], fn board ->
        per_color(board, fn board, color ->
          enemies = AttackMap.attack_counts(board, Board.opposite(color))
          defenders = AttackMap.defender_counts(board, color)

          own_non_king(board, color)
          |> Enum.filter(fn square ->
            not Map.has_key?(defenders, square) and Map.has_key?(enemies, square)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("attacks.hanging", 10, [{10, "hanging pieces"}], fn board ->
        per_color(board, fn board, color ->
          enemies = AttackMap.attack_counts(board, Board.opposite(color))
          defenders = AttackMap.defender_counts(board, color)

          own_non_king(board, color)
          |> Enum.filter(fn square ->
            not Map.has_key?(defenders, square) and Map.get(enemies, square, 0) >= 2
          end)
          |> to_alg()
        end)
      end),
      Feature.new("attacks.en_prise", 10, [{10, "en prise pieces"}], fn board ->
        per_color(board, fn board, color ->
          enemies = AttackMap.attack_counts(board, Board.opposite(color))
          defenders = AttackMap.defender_counts(board, color)

          own_non_king(board, color)
          |> Enum.filter(fn square ->
            Map.get(enemies, square, 0) > Map.get(defenders, square, 0)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("attacks.overprotected", 10, [{10, "overprotected pieces"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> AttackMap.defender_counts(color)
          |> Map.filter(fn {_square, count} -> count >= 3 end)
          |> Map.keys()
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("attacks.overloaded", 10, [{10, "overloaded defender"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.color_occupancy(board, color)
          enemy_attacks = AttackMap.attack_counts(board, Board.opposite(color))

          pieces(board, color)
          |> Enum.filter(fn {type, square} ->
            attacks = piece_attacks(board, color, type, square)

            defended =
              (attacks &&& own &&& bnot(1 <<< square))
              |> Support.popcount()

            defended >= 2 and Map.get(enemy_attacks, square, 0) >= 1
          end)
          |> Enum.map(fn {_type, square} -> Square.to_string(square) end)
          |> to_alg()
        end)
      end),
      Feature.new("attacks.underdefended", 10, [{10, "underdefended piece"}], fn board ->
        per_color(board, fn board, color ->
          enemies = AttackMap.attack_counts(board, Board.opposite(color))
          defenders = AttackMap.defender_counts(board, color)

          own_non_king(board, color)
          |> Enum.filter(fn square ->
            atk = Map.get(enemies, square, 0)
            dfn = Map.get(defenders, square, 0)

            dfn >= 1 and atk >= dfn + 1
          end)
          |> to_alg()
        end)
      end),
      Feature.new(
        "attacks.force_ratio",
        10,
        [{10, "aanvaller-verdedigerverhouding op een doelveld"}],
        fn board ->
          per_color(board, fn board, color ->
            enemies = AttackMap.attack_counts(board, Board.opposite(color))
            defenders = AttackMap.defender_counts(board, color)

            ratios =
              defenders
              |> Enum.filter(fn {square, _count} -> Map.get(enemies, square, 0) >= 1 end)
              |> Enum.map(fn {square, dfn} -> Map.fetch!(enemies, square) / dfn end)

            case ratios do
              [] -> nil
              _ -> round(Enum.sum(ratios) / length(ratios) * 100) / 100
            end
          end)
        end
      ),
      Feature.new(
        "attacks.pressure_squares",
        10,
        [{10, "druk op een specifiek veld"}],
        fn board ->
          per_color(board, fn board, color ->
            enemy_occ = Board.color_occupancy(board, Board.opposite(color))

            board
            |> AttackMap.attack_counts(color)
            |> Enum.filter(fn {square, count} ->
              count >= 2 and (1 <<< square &&& enemy_occ) != 0
            end)
            |> Enum.map(fn {square, _count} -> square end)
            |> Enum.sort()
            |> to_alg()
          end)
        end
      ),
      Feature.new("attacks.pressure_piece", 10, [{10, "druk op een specifiek stuk"}], fn board ->
        per_color(board, fn board, color ->
          enemy_occ = Board.color_occupancy(board, Board.opposite(color))

          list =
            board
            |> AttackMap.attack_counts(color)
            |> Enum.filter(fn {square, _count} -> (1 <<< square &&& enemy_occ) != 0 end)

          case list do
            [] ->
              nil

            list ->
              {square, _count} = Enum.max_by(list, fn {square, count} -> {count, -square} end)
              Square.to_string(square)
          end
        end)
      end),
      Feature.new(
        "attacks.pressure_isolated",
        10,
        [{10, "pressure on isolated pawn"}],
        fn board ->
          per_color(board, fn board, color ->
            enemy = Board.opposite(color)

            board
            |> enemy_isolated_pawns(enemy)
            |> Enum.filter(&(AttackMap.attackers(board, &1, color) >= 2))
            |> to_alg()
          end)
        end
      ),
      Feature.new(
        "attacks.pressure_backward",
        10,
        [{10, "pressure on backward pawn"}],
        fn board ->
          per_color(board, fn board, color ->
            enemy = Board.opposite(color)

            board
            |> enemy_backward_pawns(enemy)
            |> Enum.filter(&(AttackMap.attackers(board, &1, color) >= 2))
            |> to_alg()
          end)
        end
      ),
      Feature.new("attacks.pressure_passed", 10, [{10, "pressure on passed pawn"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)

          board
          |> Support.passed_pawns(enemy)
          |> Enum.filter(&(AttackMap.attackers(board, &1, color) >= 2))
          |> to_alg()
        end)
      end),
      Feature.new("attacks.f2_f7", 10, [{10, "pressure on f2/f7"}], fn board ->
        per_color(board, fn board, color ->
          square = if color == :white, do: 13, else: 53
          AttackMap.attackers(board, square, Board.opposite(color))
        end)
      end),
      Feature.new("attacks.king_zone_pressure", 10, [{10, "pressure on king zone"}], fn board ->
        per_color(board, fn board, color ->
          enemy_attacks = AttackMap.attacked_bb(board, Board.opposite(color))

          board
          |> king_ring(color)
          |> Enum.filter(&((1 <<< &1 &&& enemy_attacks) != 0))
          |> to_alg()
        end)
      end)
    ]
  end

  defp attacked_squares(board, color) do
    board |> AttackMap.attacked_bb(color) |> Bitboard.squares() |> to_alg()
  end

  defp own_non_king(board, color) do
    board
    |> Board.color_occupancy(color)
    |> Bitboard.squares()
    |> Enum.filter(fn square -> Board.piece_at(board, square) != {color, :kings} end)
  end

  defp pieces(board, color) do
    for type <- Board.types(),
        square <- Bitboard.squares(Board.piece_bb(board, color, type)),
        do: {type, square}
  end

  defp piece_attacks(_board, color, :pawns, square) do
    if color == :white, do: AttackTables.white_pawn(square), else: AttackTables.black_pawn(square)
  end

  defp piece_attacks(_board, _color, :knights, square), do: AttackTables.knight(square)
  defp piece_attacks(_board, _color, :kings, square), do: AttackTables.king(square)

  defp piece_attacks(board, _color, :bishops, square),
    do: AttackTables.bishop_attacks(square, Board.occupancy(board))

  defp piece_attacks(board, _color, :rooks, square),
    do: AttackTables.rook_attacks(square, Board.occupancy(board))

  defp piece_attacks(board, _color, :queens, square),
    do: AttackTables.queen_attacks(square, Board.occupancy(board))

  defp enemy_isolated_pawns(board, color) do
    groups = Support.pawns_by_file(board, color)

    pawn_squares(board, color)
    |> Enum.filter(fn square ->
      file = Square.file(square)
      not (Map.has_key?(groups, file - 1) or Map.has_key?(groups, file + 1))
    end)
  end

  defp enemy_backward_pawns(board, color) do
    groups = Support.pawns_by_file(board, color)

    pawn_squares(board, color)
    |> Enum.filter(fn square ->
      file = Square.file(square)
      rank = Square.rank(square)

      not Enum.any?([-1, 1], fn offset ->
        groups
        |> Map.get(file + offset, [])
        |> Enum.any?(&rear_or_level?(&1, rank, color))
      end)
    end)
  end

  defp rear_or_level?(rank, own, :white), do: rank <= own
  defp rear_or_level?(rank, own, :black), do: rank >= own

  defp pawn_squares(board, color) do
    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp king_ring(board, color) do
    case Bitboard.squares(Board.piece_bb(board, color, :kings)) do
      [] ->
        []

      [king] ->
        file = Square.file(king)
        rank = Square.rank(king)

        for f <- (file - 1)..(file + 1),
            r <- (rank - 1)..(rank + 1),
            f in 0..7,
            r in 0..7,
            f != file or r != rank,
            do: r * 8 + f
    end
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
