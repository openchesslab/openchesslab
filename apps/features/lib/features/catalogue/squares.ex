defmodule Features.Catalogue.Squares do
  @moduledoc """
  Spec section 8 — squares and weaknesses.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support}
  alias Features.Chess.{AttackTables, Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("squares.weak", 8, [{8, "weak square"}], fn board ->
        per_color(board, fn board, color ->
          own_half = Support.enemy_half_bb(Board.opposite(color))
          enemy = Board.opposite(color)

          empty_squares(board)
          |> Enum.filter(fn square ->
            (1 <<< square &&& own_half) != 0 and
              Support.attacked_by_pawn?(board, square, enemy) and
              not Support.attacked_by_pawn?(board, square, color)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("squares.hole", 8, [{8, "hole"}], fn board ->
        per_color(board, fn board, color ->
          own_half = Support.enemy_half_bb(Board.opposite(color))

          empty_squares(board)
          |> Enum.filter(fn square ->
            (1 <<< square &&& own_half) != 0 and
              not Support.attacked_by_pawn?(board, square, color)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("squares.outpost", 8, [{8, "outpost square"}], fn board ->
        per_color(board, fn board, color ->
          empty_squares(board)
          |> Enum.filter(&outpost_base?(board, &1, color))
          |> to_alg()
        end)
      end),
      Feature.new("squares.occupied_outpost", 8, [{8, "occupied outpost"}], fn board ->
        per_color(board, fn board, color ->
          Board.color_occupancy(board, color)
          |> Bitboard.squares()
          |> Enum.filter(&outpost_base?(board, &1, color))
          |> to_alg()
        end)
      end),
      Feature.new("squares.potential_outpost", 8, [{8, "potential outpost"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)
          half = Support.enemy_half_bb(color)

          empty_squares(board)
          |> Enum.filter(fn square ->
            (1 <<< square &&& half) != 0 and
              not Support.attacked_by_pawn?(board, square, enemy)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("squares.weak_color_complex", 8, [{8, "weak color complex"}], fn board ->
        per_color(board, fn board, color ->
          %{light: light, dark: dark} = pawn_complex_counts(board, color)

          cond do
            dark <= light - 3 -> "light"
            light <= dark - 3 -> "dark"
            true -> nil
          end
        end)
      end),
      Feature.new("squares.dark_weakness", 8, [{8, "dark-square weakness"}], fn board ->
        per_color(board, fn board, color ->
          complex = weak_complex(board, color)
          complex != nil and complex == :dark
        end)
      end),
      Feature.new("squares.light_weakness", 8, [{8, "light-square weakness"}], fn board ->
        per_color(board, fn board, color ->
          complex = weak_complex(board, color)
          complex != nil and complex == :light
        end)
      end),
      Feature.new("squares.king_weak", 8, [{8, "zwakke velden rond koning"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)
          attackers = AttackMap.attack_counts(board, enemy)
          defenders = AttackMap.attack_counts(board, color)

          king_ring(board, color)
          |> Enum.filter(fn square ->
            Map.has_key?(attackers, square) and not Map.has_key?(defenders, square)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("squares.behind_pawns", 8, [{8, "zwakke velden achter pionnen"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)
          attackers = AttackMap.attack_counts(board, enemy)
          occupancy = Board.occupancy(board)

          Board.piece_bb(board, color, :pawns)
          |> Bitboard.squares()
          |> Enum.map(&behind_square(&1, color))
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(fn square ->
            (1 <<< square &&& occupancy) == 0 and Map.has_key?(attackers, square)
          end)
          |> Enum.uniq()
          |> to_alg()
        end)
      end),
      Feature.new("squares.invasion", 8, [{8, "invasion square"}], fn board ->
        per_color(board, fn board, color ->
          invasion_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new("squares.heavy_entry", 8, [{8, "entry square voor zware stukken"}], fn board ->
        per_color(board, fn board, color ->
          heavy = heavy_attack_bits(board, color)
          invasion = invasion_squares(board, color)

          invasion
          |> Enum.filter(&((1 <<< &1 &&& heavy) != 0))
          |> to_alg()
        end)
      end),
      Feature.new(
        "squares.weakness_duration",
        8,
        [{8, "permanent versus tijdelijke zwakte"}],
        fn board ->
          per_color(board, fn board, color ->
            enemy = Board.opposite(color)
            attackers = AttackMap.attack_counts(board, enemy)
            own_half = Support.enemy_half_bb(Board.opposite(color))

            weak =
              empty_squares(board)
              |> Enum.filter(fn square ->
                (1 <<< square &&& own_half) != 0 and
                  Support.attacked_by_pawn?(board, square, enemy) and
                  not Support.attacked_by_pawn?(board, square, color)
              end)

            %{
              "permanent" => weak |> Enum.filter(&(Map.fetch!(attackers, &1) >= 2)) |> to_alg(),
              "temporary" => weak |> Enum.filter(&(Map.fetch!(attackers, &1) == 1)) |> to_alg()
            }
          end)
        end
      )
    ]
  end

  defp outpost_base?(board, square, color) do
    half = Support.enemy_half_bb(color)
    enemy = Board.opposite(color)

    (1 <<< square &&& half) != 0 and
      Support.attacked_by_pawn?(board, square, color) and
      not Support.attacked_by_pawn?(board, square, enemy)
  end

  defp invasion_squares(board, color) do
    half = Support.enemy_half_bb(color)
    enemy = Board.opposite(color)
    enemy_attacks = AttackMap.attacked_bb(board, enemy)

    (AttackMap.attacked_bb(board, color) &&& half &&& bnot(enemy_attacks))
    |> Bitboard.squares()
    |> Enum.filter(&is_empty(board, &1))
    |> Enum.sort()
  end

  defp heavy_attack_bits(board, color) do
    occupancy = Board.occupancy(board)

    rook_bits =
      board
      |> Board.piece_bb(color, :rooks)
      |> Bitboard.squares()
      |> Enum.reduce(0, fn square, union ->
        union ||| AttackTables.rook_attacks(square, occupancy)
      end)

    queen_bits =
      board
      |> Board.piece_bb(color, :queens)
      |> Bitboard.squares()
      |> Enum.reduce(0, fn square, union ->
        union ||| AttackTables.queen_attacks(square, occupancy)
      end)

    rook_bits ||| queen_bits
  end

  defp pawn_complex_counts(board, color) do
    Board.piece_bb(board, color, :pawns)
    |> Bitboard.squares()
    |> Enum.reduce(%{light: 0, dark: 0}, fn square, counts ->
      Map.update!(counts, Support.square_color(square), &(&1 + 1))
    end)
  end

  defp weak_complex(board, color) do
    %{light: light, dark: dark} = pawn_complex_counts(board, color)

    cond do
      dark <= light - 3 -> :light
      light <= dark - 3 -> :dark
      true -> nil
    end
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

  defp behind_square(square, color) do
    rank = Square.rank(square)

    cond do
      color == :white and rank > 0 -> square - 8
      color == :black and rank < 7 -> square + 8
      true -> nil
    end
  end

  defp empty_squares(board) do
    occupancy = Board.occupancy(board)

    0..63
    |> Enum.filter(&((1 <<< &1 &&& occupancy) == 0))
  end

  defp is_empty(board, square) do
    (Board.occupancy(board) &&& 1 <<< square) == 0
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
