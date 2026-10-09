defmodule Features.Catalogue.Evaluation do
  @moduledoc """
  Spec section 20 — eval properties: a white-relative total evaluation
  built from material, mobility, space, king safety, initiative,
  development, pawn structure, activity and tactical resources, plus
  the individual advantage components and a win/draw/loss tendency.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("evaluation.total_evaluation", 20, [{20, "totale evaluatie"}], fn board ->
        total(board)
      end),
      Feature.new("evaluation.material_advantage", 20, [{20, "material advantage"}], fn board ->
        diffs(board).material
      end),
      Feature.new(
        "evaluation.positional_advantage",
        20,
        [{20, "positional advantage"}],
        fn board ->
          positional(board)
        end
      ),
      Feature.new("evaluation.space_advantage", 20, [{20, "space advantage"}], fn board ->
        diffs(board).space
      end),
      Feature.new("evaluation.mobility_advantage", 20, [{20, "mobility advantage"}], fn board ->
        diffs(board).mobility
      end),
      Feature.new(
        "evaluation.king_safety_advantage",
        20,
        [{20, "king-safety advantage"}],
        fn board ->
          diffs(board).king_safety
        end
      ),
      Feature.new(
        "evaluation.initiative_advantage",
        20,
        [{20, "initiative advantage"}],
        fn board ->
          diffs(board).initiative
        end
      ),
      Feature.new(
        "evaluation.development_advantage",
        20,
        [{20, "development advantage"}],
        fn board ->
          diffs(board).development
        end
      ),
      Feature.new(
        "evaluation.pawn_structure_advantage",
        20,
        [{20, "pawn-structure advantage"}],
        fn board ->
          diffs(board).pawn_structure
        end
      ),
      Feature.new(
        "evaluation.piece_activity_advantage",
        20,
        [{20, "piece-activity advantage"}],
        fn board ->
          diffs(board).activity
        end
      ),
      Feature.new("evaluation.tactical_advantage", 20, [{20, "tactical advantage"}], fn board ->
        diffs(board).tactical
      end),
      Feature.new("evaluation.attack_strength", 20, [{20, "attack strength"}], fn board ->
        diffs(board).attack
      end),
      Feature.new("evaluation.defensive_strength", 20, [{20, "defensive strength"}], fn board ->
        diffs(board).defense
      end),
      Feature.new("evaluation.compensation", 20, [{20, "compensation"}], fn board ->
        positional(board)
      end),
      Feature.new(
        "evaluation.winning_drawing_losing",
        20,
        [{20, "winning/drawing/losing tendency"}],
        fn board ->
          tendency(total(board))
        end
      )
    ]
  end

  @doc """
  The advantage-component map shared by every feature in this section.
  `Features.extract/2` computes it once and stashes it on the board's
  `evaluation_cache` field; this reader reuses it.
  """
  @spec workspace(Board.t()) :: map()
  def workspace(%Board{evaluation_cache: cache}) when is_map(cache), do: cache
  def workspace(board), do: build_diffs(board)

  defp diffs(%Board{evaluation_cache: cache}) when is_map(cache), do: cache
  defp diffs(board), do: build_diffs(board)

  defp build_diffs(board) do
    material = Support.material_value(board, :white) - Support.material_value(board, :black)

    %{
      material: material,
      mobility: mobility_diff(board),
      space: space_diff(board),
      king_safety: king_safety_diff(board),
      initiative: initiative_diff(board),
      development: development_diff(board),
      pawn_structure: pawn_structure_diff(board),
      activity: activity_diff(board),
      tactical: tactical_diff(board),
      attack: attack_diff(board),
      defense: defense_diff(board)
    }
  end

  defp total(board) do
    d = diffs(board)

    raw =
      1.0 * d.material + 0.10 * d.mobility + 0.10 * d.space + 0.05 * d.king_safety +
        0.10 * d.initiative + 0.10 * d.development + 0.10 * d.pawn_structure +
        0.05 * d.activity + 0.10 * d.tactical + 0.05 * d.attack + 0.05 * d.defense

    Float.round(raw, 2)
  end

  defp positional(board) do
    d = diffs(board)

    raw_non_material =
      0.10 * d.mobility + 0.10 * d.space + 0.05 * d.king_safety + 0.10 * d.initiative +
        0.10 * d.development + 0.10 * d.pawn_structure + 0.05 * d.activity +
        0.10 * d.tactical + 0.05 * d.attack + 0.05 * d.defense

    Float.round(raw_non_material, 2)
  end

  defp mobility_diff(board) do
    MobilityMap.total(board, :white) - MobilityMap.total(board, :black)
  end

  defp space_diff(board) do
    half_pawns(board, :white) - half_pawns(board, :black)
  end

  defp half_pawns(board, color) do
    Support.popcount(Board.piece_bb(board, color, :pawns) &&& Support.enemy_half_bb(color))
  end

  defp king_safety_diff(board) do
    king_zone_attacks(board, :black) - king_zone_attacks(board, :white)
  end

  defp king_zone_attacks(board, color) do
    enemy = Board.opposite(color)

    case TacticMap.king_square(board, color) do
      nil ->
        0

      king ->
        zone = TacticMap.king_ring_bb(board, color) ||| 1 <<< king
        counts = AttackMap.attack_counts(board, enemy)

        zone
        |> Bitboard.squares()
        |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
    end
  end

  defp initiative_diff(board) do
    pressure_score(board, :white) - pressure_score(board, :black)
  end

  defp pressure_score(board, color) do
    length(TacticMap.checks(board, color)) + length(TacticMap.captures(board, color)) +
      length(TacticMap.multi_attackers(board, color, [:pawns, :knights]))
  end

  defp development_diff(board) do
    development(board, :white) - development(board, :black)
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

  defp pawn_structure_diff(board) do
    pawn_structure(board, :white) - pawn_structure(board, :black)
  end

  defp pawn_structure(board, color) do
    3 * length(Support.passed_pawns(board, color)) -
      length(Support.isolated_pawns(board, color)) -
      length(Support.backward_pawns(board, color))
  end

  defp activity_diff(board) do
    activity(board, :white) - activity(board, :black)
  end

  defp activity(board, color) do
    MobilityMap.total(board, color) + attacking_potential(board, color)
  end

  defp tactical_diff(board) do
    tactical(board, :white) - tactical(board, :black)
  end

  defp tactical(board, color) do
    length(TacticMap.checks(board, color)) + length(TacticMap.captures(board, color)) +
      length(TacticMap.multi_attackers(board, color, [:pawns, :knights])) +
      map_size(TacticMap.pins(board, color)) + length(TacticMap.skewers(board, color))
  end

  defp attack_diff(board) do
    ring_attack(board, :white) - ring_attack(board, :black)
  end

  defp ring_attack(board, color) do
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

  defp defense_diff(board) do
    defended_pieces(board, :white) - defended_pieces(board, :black)
  end

  defp defended_pieces(board, color) do
    board
    |> TacticMap.pieces_squares(color)
    |> Enum.count(&(AttackMap.attackers(board, &1, color) >= 1))
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

  defp tendency(total) do
    cond do
      total >= 1.5 -> %{"white" => "winning", "black" => "losing"}
      total <= -1.5 -> %{"white" => "losing", "black" => "winning"}
      true -> %{"white" => "drawing", "black" => "drawing"}
    end
  end
end
