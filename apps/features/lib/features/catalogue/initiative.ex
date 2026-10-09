defmodule Features.Catalogue.Initiative do
  @moduledoc """
  Spec section 18 — initiative and dynamics: tempo, development lead,
  momentum, forcing-move density, attacking and defending loads and
  compensation for material deficits.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("initiative.initiative", 18, [{18, "initiatief"}], fn board ->
        per_color(board, fn board, color ->
          pressure_score(board, color) > pressure_score(board, Board.opposite(color))
        end)
      end),
      Feature.new("initiative.tempo_advantage", 18, [{18, "tempo advantage"}], fn board ->
        per_color(board, fn board, color ->
          board.side_to_move == color and
            development(board, color) >= development(board, Board.opposite(color))
        end)
      end),
      Feature.new("initiative.development_lead", 18, [{18, "development lead"}], fn board ->
        per_color(board, fn board, color ->
          development(board, color) - development(board, Board.opposite(color))
        end)
      end),
      Feature.new("initiative.attacking_momentum", 18, [{18, "attacking momentum"}], fn board ->
        per_color(board, fn board, color ->
          ring_attack_count(board, color) >= 3 and
            ring_attack_count(board, Board.opposite(color)) == 0
        end)
      end),
      Feature.new(
        "initiative.forcing_move_density",
        18,
        [{18, "forcing-move density"}],
        fn board ->
          per_color(board, &forcing_density/2)
        end
      ),
      Feature.new("initiative.tactical_potential", 18, [{18, "tactical potential"}], fn board ->
        per_color(board, &tactical_potential/2)
      end),
      Feature.new("initiative.attacking_potential", 18, [{18, "attacking potential"}], fn board ->
        per_color(board, &attacking_potential/2)
      end),
      Feature.new("initiative.defending_burden", 18, [{18, "defending burden"}], fn board ->
        per_color(board, &defending_burden/2)
      end),
      Feature.new(
        "initiative.ability_to_create_threats",
        18,
        [{18, "ability to create threats"}],
        fn board ->
          per_color(board, &ability_to_create_threats/2)
        end
      ),
      Feature.new(
        "initiative.dynamic_compensation",
        18,
        [{18, "dynamic compensation"}],
        fn board ->
          per_color(board, &dynamic_compensation?/2)
        end
      ),
      Feature.new(
        "initiative.positional_compensation",
        18,
        [{18, "positional compensation"}],
        fn board ->
          per_color(board, &positional_compensation?/2)
        end
      ),
      Feature.new(
        "initiative.sacrifice_compensation",
        18,
        [{18, "sacrifice compensation"}],
        fn board ->
          per_color(board, &sacrifice_compensation?/2)
        end
      )
    ]
  end

  defp pressure_score(board, color) do
    length(TacticMap.checks(board, color)) + length(TacticMap.captures(board, color)) +
      length(TacticMap.multi_attackers(board, color, [:pawns, :knights]))
  end

  defp development(board, color) do
    back = back_rank(color)

    [:knights, :bishops, :rooks, :queens]
    |> Enum.reduce(0, fn type, acc ->
      acc +
        (board
         |> Board.piece_bb(color, type)
         |> Bitboard.squares()
         |> Enum.count(&(Square.rank(&1) != back)))
    end)
  end

  defp back_rank(:white), do: 0
  defp back_rank(:black), do: 7

  defp ring_attack_count(board, color) do
    enemy = Board.opposite(color)

    case TacticMap.king_square(board, enemy) do
      nil ->
        0

      king ->
        zone = TacticMap.king_ring_bb(board, enemy) ||| 1 <<< king
        counts = AttackMap.attack_counts(board, color)

        zone
        |> Bitboard.squares()
        |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
    end
  end

  defp forcing_density(board, color) do
    moves = TacticMap.pseudo_moves(board, color)

    if moves == [] do
      0.0
    else
      Float.round(length(TacticMap.forcing(board, color)) / length(moves), 3)
    end
  end

  defp tactical_potential(board, color) do
    length(TacticMap.checks(board, color)) + length(TacticMap.captures(board, color)) +
      length(TacticMap.multi_attackers(board, color, [:pawns, :knights])) +
      map_size(TacticMap.pins(board, color)) + length(TacticMap.skewers(board, color))
  end

  defp attacking_potential(board, color) do
    enemy =
      board
      |> TacticMap.enemy_piece_bb(color)

    counts = AttackMap.attack_counts(board, color)

    enemy
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
  end

  defp defending_burden(board, color) do
    own = Board.color_occupancy(board, color) &&& bnot(Board.piece_bb(board, color, :kings))

    counts = AttackMap.attack_counts(board, Board.opposite(color))

    own
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
  end

  defp ability_to_create_threats(board, color) do
    enemy = TacticMap.enemy_piece_bb(board, color)
    captures = MapSet.new(TacticMap.captures(board, color), &move_key/1)

    board
    |> TacticMap.pseudo_moves(color)
    |> Enum.count(fn move ->
      not MapSet.member?(captures, move_key(move)) and
        (TacticMap.post_move_attack(board, move, color) &&& enemy) != 0
    end)
  end

  defp move_key(move), do: {move.from, move.to, move.promotion}

  defp dynamic_compensation?(board, color) do
    enemy = Board.opposite(color)

    material_lag?(board, color) and
      attacking_potential(board, color) > attacking_potential(board, enemy)
  end

  defp material_lag?(board, color) do
    enemy = Board.opposite(color)

    Support.material_value(board, color) - Support.material_value(board, enemy) <= -2
  end

  defp positional_compensation?(board, color) do
    enemy = Board.opposite(color)

    material_down?(board, color) and
      MobilityMap.total(board, color) - MobilityMap.total(board, enemy) >= 4
  end

  defp material_down?(board, color) do
    enemy = Board.opposite(color)

    Support.material_value(board, color) - Support.material_value(board, enemy) <= -1
  end

  defp sacrifice_compensation?(board, color) do
    enemy = Board.opposite(color)

    material_down?(board, color) and
      (map_size(TacticMap.pins(board, color)) > 0 or TacticMap.trapped_squares(board, enemy) != [])
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end
end
