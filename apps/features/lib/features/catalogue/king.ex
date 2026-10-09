defmodule Features.Catalogue.King do
  @moduledoc """
  Spec section 11 — king safety.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @values %{pawns: 1, knights: 3, bishops: 3, rooks: 5, queens: 9}

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("king.castled", 11, [{11, "koning heeft gerokeerd"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil -> false
            king -> Square.rank(king) == back_rank(color) and Square.file(king) in [1, 2, 5, 6]
          end
        end)
      end),
      Feature.new("king.castled_kingside", 11, [{11, "kingside castled"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil -> false
            king -> Square.rank(king) == back_rank(color) and Square.file(king) in [5, 6]
          end
        end)
      end),
      Feature.new("king.castled_queenside", 11, [{11, "queenside castled"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil -> false
            king -> Square.rank(king) == back_rank(color) and Square.file(king) in [1, 2]
          end
        end)
      end),
      Feature.new("king.uncastled", 11, [{11, "uncastled king"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil -> false
            king -> Square.rank(king) == back_rank(color) and Square.file(king) == 4
          end
        end)
      end),
      Feature.new("king.center", 11, [{11, "koning nog in het centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil -> false
            king -> (1 <<< king &&& center) != 0
          end
        end)
      end),
      Feature.new("king.castle_rights_lost", 11, [{11, "verloren rokaderecht"}], fn board ->
        per_color(board, fn board, color ->
          not Board.can_castle?(board, color, :kingside) and
            not Board.can_castle?(board, color, :queenside)
        end)
      end),
      Feature.new("king.shield", 11, [{11, "pawn shield"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)

          board
          |> shield_squares(color)
          |> Enum.filter(&((1 <<< &1 &&& own) != 0))
          |> to_alg()
        end)
      end),
      Feature.new("king.missing_shield", 11, [{11, "ontbrekende shield pawns"}], fn board ->
        per_color(board, fn board, color ->
          occupancy = Board.occupancy(board)

          board
          |> shield_squares(color)
          |> Enum.filter(&((1 <<< &1 &&& occupancy) == 0))
          |> to_alg()
        end)
      end),
      Feature.new(
        "king.weak_shield_pawns",
        11,
        [{11, "verzwakte pionnen rond koning"}],
        fn board ->
          per_color(board, fn board, color ->
            own = Board.piece_bb(board, color, :pawns)
            groups = Support.pawns_by_file(board, color)

            board
            |> shield_squares(color)
            |> Enum.filter(&((1 <<< &1 &&& own) != 0))
            |> Enum.filter(fn square ->
              isolated?(square, groups) or backward?(square, color, groups)
            end)
            |> to_alg()
          end)
        end
      ),
      Feature.new("king.open_file", 11, [{11, "open file naar koning"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil ->
              false

            king ->
              own = Board.piece_bb(board, color, :pawns)
              (own &&& Support.file_bb(Square.file(king))) == 0
          end
        end)
      end),
      Feature.new("king.semi_open_file", 11, [{11, "semi-open file naar koning"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil ->
              false

            king ->
              own = Board.piece_bb(board, color, :pawns)
              enemy = Board.piece_bb(board, Board.opposite(color), :pawns)
              file = Support.file_bb(Square.file(king))

              (own &&& file) == 0 and (enemy &&& file) != 0
          end
        end)
      end),
      Feature.new("king.open_diagonal", 11, [{11, "open diagonal naar koning"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)

          case king_square(board, color) do
            nil -> []
            king -> diagonals_through(king, own)
          end
        end)
      end),
      Feature.new("king.exposed", 11, [{11, "exposed king"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)

          board
          |> shield_squares(color)
          |> Enum.any?(&((1 <<< &1 &&& own) != 0))
          |> Kernel.not()
        end)
      end),
      Feature.new("king.zone", 11, [{11, "king zone"}], fn board ->
        per_color(board, fn board, color ->
          board |> king_ring(color) |> to_alg()
        end)
      end),
      Feature.new("king.attackers", 11, [{11, "aantal aanvallers rond koning"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> attackers_on_ring(color)
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("king.defenders", 11, [{11, "aantal verdedigers rond koning"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> defenders_on_ring(color)
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("king.attack_power", 11, [{11, "aanvalskracht rond koning"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> attackers_on_ring(color)
          |> Bitboard.squares()
          |> Enum.reduce(0, fn square, total ->
            case Board.piece_at(board, square) do
              {_enemy, type} -> total + Map.get(@values, type, 0)
              nil -> total
            end
          end)
        end)
      end),
      Feature.new("king.escape_squares", 11, [{11, "escape squares"}], fn board ->
        per_color(board, fn board, color ->
          enemy_attacks = AttackMap.attack_counts(board, Board.opposite(color))
          occupancy = Board.occupancy(board)

          board
          |> king_ring(color)
          |> Enum.filter(fn square ->
            (1 <<< square &&& occupancy) == 0 and not Map.has_key?(enemy_attacks, square)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("king.limited_escapes", 11, [{11, "beperkte vluchtvelden"}], fn board ->
        per_color(board, fn board, color ->
          enemy_attacks = AttackMap.attack_counts(board, Board.opposite(color))
          occupancy = Board.occupancy(board)

          escapes =
            board
            |> king_ring(color)
            |> Enum.count(fn square ->
              (1 <<< square &&& occupancy) == 0 and not Map.has_key?(enemy_attacks, square)
            end)

          escapes <= 1
        end)
      end),
      Feature.new("king.back_rank_weakness", 11, [{11, "back-rank weakness"}], fn board ->
        per_color(board, fn board, color ->
          case king_square(board, color) do
            nil ->
              false

            king ->
              back_rank?(king, color) and front_blocked?(board, king, color) and
                enemy_heavy?(board, color)
          end
        end)
      end),
      Feature.new("king.mating_net", 11, [{11, "mating-net pressure"}], fn board ->
        per_color(board, fn board, color ->
          attacker_count = board |> attackers_on_ring(color) |> Support.popcount()
          enemy_attacks = AttackMap.attack_counts(board, Board.opposite(color))
          occupancy = Board.occupancy(board)

          escapes =
            board
            |> king_ring(color)
            |> Enum.count(fn square ->
              (1 <<< square &&& occupancy) == 0 and not Map.has_key?(enemy_attacks, square)
            end)

          attacker_count >= 3 and escapes <= 1
        end)
      end),
      Feature.new("king.opposite_side_castling", 11, [{11, "opposite-side castling"}], fn board ->
        white = castling_side(board, :white)
        black = castling_side(board, :black)

        (white == :kingside and black == :queenside) or
          (white == :queenside and black == :kingside)
      end),
      Feature.new("king.safety_advantage", 11, [{11, "king-safety advantage"}], fn board ->
        king_safety(board, :white) - king_safety(board, :black)
      end)
    ]
  end

  defp king_safety(board, color) do
    defenders = board |> defenders_on_ring(color) |> Support.popcount()
    attackers = board |> attackers_on_ring(color) |> Support.popcount()
    missing = length(king_missing_shield(board, color))
    castled = castled?(board, color)

    defenders - 2 * attackers - 2 * missing + if(castled, do: 3, else: 0)
  end

  defp castled?(board, color) do
    case king_square(board, color) do
      nil -> false
      king -> Square.rank(king) == back_rank(color) and Square.file(king) in [1, 2, 5, 6]
    end
  end

  defp defenders_on_ring(board, color) do
    ring = ring_bb(board, color)
    own = Board.color_occupancy(board, color)
    king = king_bb(board, color)

    AttackMap.attackers_into(board, color, ring) &&& own &&& bnot(king)
  end

  defp attackers_on_ring(board, color) do
    AttackMap.attackers_into(board, Board.opposite(color), ring_bb(board, color))
  end

  defp king_missing_shield(board, color) do
    occupancy = Board.occupancy(board)

    board
    |> shield_squares(color)
    |> Enum.filter(&((1 <<< &1 &&& occupancy) == 0))
  end

  defp shield_squares(board, color) do
    case king_square(board, color) do
      nil ->
        []

      king ->
        file = Square.file(king)
        rank = Square.rank(king)
        ranks = if color == :white, do: [rank + 1, rank + 2], else: [rank - 1, rank - 2]

        for f <- (file - 1)..(file + 1),
            r <- ranks,
            f in 0..7,
            r in 0..7,
            do: r * 8 + f
    end
  end

  defp king_ring(board, color) do
    case king_square(board, color) do
      nil ->
        []

      king ->
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

  defp ring_bb(board, color) do
    board
    |> king_ring(color)
    |> Enum.reduce(0, fn square, bits -> bits ||| 1 <<< square end)
  end

  defp diagonals_through(king, own_pawns) do
    file = Square.file(king)
    rank = Square.rank(king)

    forward =
      for offset <- -7..7,
          f = file + offset,
          r = rank + offset,
          f in 0..7,
          r in 0..7,
          do: r * 8 + f

    backward =
      for offset <- -7..7,
          f = file + offset,
          r = rank - offset,
          f in 0..7,
          r in 0..7,
          do: r * 8 + f

    [forward, backward]
    |> Enum.filter(fn squares ->
      bits = Enum.reduce(squares, 0, fn square, bits -> bits ||| 1 <<< square end)
      (bits &&& own_pawns) == 0
    end)
    |> Enum.map(&label/1)
    |> Enum.sort()
  end

  defp label(squares) do
    sorted = Enum.sort(squares)
    Square.to_string(List.first(sorted)) <> Square.to_string(List.last(sorted))
  end

  defp castling_side(board, color) do
    cond do
      not Board.can_castle?(board, color, :kingside) -> nil
      not Board.can_castle?(board, color, :queenside) -> nil
      Square.file(king_square(board, color)) in [5, 6] -> :kingside
      Square.file(king_square(board, color)) in [1, 2] -> :queenside
      true -> nil
    end
  end

  defp back_rank?(king, :white), do: Square.rank(king) == 0
  defp back_rank?(king, :black), do: Square.rank(king) == 7

  defp front_blocked?(board, king, color) do
    file = Square.file(king)
    rank = Square.rank(king)
    forward = if color == :white, do: rank + 1, else: rank - 1

    forward in 0..7 and
      Enum.all?([file - 1, file, file + 1], fn f ->
        f not in 0..7 or Board.piece_at(board, forward * 8 + f) != nil
      end)
  end

  defp enemy_heavy?(board, color) do
    enemy = Board.opposite(color)
    Board.piece_bb(board, enemy, :rooks) != 0 or Board.piece_bb(board, enemy, :queens) != 0
  end

  defp isolated?(square, groups) do
    file = Square.file(square)
    not (Map.has_key?(groups, file - 1) or Map.has_key?(groups, file + 1))
  end

  defp backward?(square, color, groups) do
    file = Square.file(square)
    rank = Square.rank(square)

    not Enum.any?([-1, 1], fn offset ->
      groups
      |> Map.get(file + offset, [])
      |> Enum.any?(&rear_or_level?(&1, rank, color))
    end)
  end

  defp rear_or_level?(rank, own, :white), do: rank <= own
  defp rear_or_level?(rank, own, :black), do: rank >= own

  defp king_square(board, color) do
    case Bitboard.squares(Board.piece_bb(board, color, :kings)) do
      [] -> nil
      [king] -> king
    end
  end

  defp king_bb(board, color), do: Board.piece_bb(board, color, :kings)

  defp back_rank(color), do: if(color == :white, do: 0, else: 7)

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
