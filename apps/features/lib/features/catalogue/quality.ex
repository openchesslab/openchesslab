defmodule Features.Catalogue.Quality do
  @moduledoc """
  Spec section 17 — piece quality and relations: bishop complexes,
  outposts, active/passive sliders, coordination, batteries and the
  best- and worst-placed pieces.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("quality.good_bishop", 17, [{17, "good bishop"}], fn board ->
        per_color(board, &good_bishops/2)
      end),
      Feature.new("quality.bad_bishop", 17, [{17, "bad bishop"}], fn board ->
        per_color(board, &bad_bishops/2)
      end),
      Feature.new(
        "quality.bishop_pawn_color_conflict",
        17,
        [{17, "bishop versus own pawn color complex"}],
        fn board ->
          per_color(board, &pawn_color_conflicts/2)
        end
      ),
      Feature.new("quality.bishop_pair", 17, [{17, "bishop pair"}], fn board ->
        per_color(board, &bishop_pair?/2)
      end),
      Feature.new(
        "quality.opposite_colored_bishops",
        17,
        [{17, "opposite-colored bishops"}],
        fn board ->
          opposite_colored_bishops?(board)
        end
      ),
      Feature.new("quality.knight_outpost", 17, [{17, "knight outpost"}], fn board ->
        per_color(board, &knight_outposts/2)
      end),
      Feature.new(
        "quality.strong_knight_vs_bad_bishop",
        17,
        [{17, "strong knight versus bad bishop"}],
        fn board ->
          per_color(board, &strong_knight_vs_bad_bishop?/2)
        end
      ),
      Feature.new("quality.active_rook", 17, [{17, "active rook"}], fn board ->
        per_color(board, &active_rooks/2)
      end),
      Feature.new("quality.passive_rook", 17, [{17, "passive rook"}], fn board ->
        per_color(board, &passive_rooks/2)
      end),
      Feature.new("quality.queen_activity", 17, [{17, "queen activity"}], fn board ->
        per_color(board, &queen_activity/2)
      end),
      Feature.new("quality.piece_coordination", 17, [{17, "piece coordination"}], fn board ->
        per_color(board, &coordination/2)
      end),
      Feature.new("quality.batteries", 17, [{17, "batteries"}], fn board ->
        per_color(board, &batteries/2)
      end),
      Feature.new("quality.connected_rooks", 17, [{17, "connected rooks"}], fn board ->
        per_color(board, &connected_rooks?/2)
      end),
      Feature.new(
        "quality.rooks_cut_off",
        17,
        [{17, "rooks cut off from each other"}],
        fn board ->
          per_color(board, &rooks_cut_off?/2)
        end
      ),
      Feature.new("quality.piece_harmony", 17, [{17, "piece harmony"}], fn board ->
        per_color(board, &harmony/2)
      end),
      Feature.new("quality.poorly_placed_piece", 17, [{17, "poorly placed piece"}], fn board ->
        per_color(board, &poorly_placed/2)
      end),
      Feature.new("quality.best_worst_placed", 17, [{17, "best/worst placed piece"}], fn board ->
        per_color(board, &best_worst/2)
      end)
    ]
  end

  defp good_bishops(board, color) do
    board
    |> bishop_squares(color)
    |> Enum.filter(&(Support.bishop_pawn_conflict(board, &1) <= 2))
    |> to_alg()
  end

  defp bad_bishops(board, color) do
    board
    |> bishop_squares(color)
    |> Enum.filter(&(Support.bishop_pawn_conflict(board, &1) >= 5))
    |> to_alg()
  end

  defp pawn_color_conflicts(board, color) do
    board
    |> bishop_squares(color)
    |> Enum.map(&Support.bishop_pawn_conflict(board, &1))
  end

  defp bishop_pair?(board, color), do: Support.piece_count(board, color, :bishops) == 2

  defp opposite_colored_bishops?(board) do
    Support.piece_count(board, :white, :bishops) == 1 and
      Support.piece_count(board, :black, :bishops) == 1 and
      Support.bishop_colors(board, :white)
      |> MapSet.difference(Support.bishop_colors(board, :black))
      |> MapSet.size() != 0
  end

  defp knight_outposts(board, color) do
    enemy = Board.opposite(color)
    half = Support.enemy_half_bb(color)

    board
    |> Board.piece_bb(color, :knights)
    |> then(&(&1 &&& half))
    |> Bitboard.squares()
    |> Enum.filter(fn square ->
      Support.attacked_by_pawn?(board, square, color) and
        not Support.attacked_by_pawn?(board, square, enemy)
    end)
    |> to_alg()
  end

  defp strong_knight_vs_bad_bishop?(board, color) do
    knight_outposts(board, color) != [] and bad_bishops(board, Board.opposite(color)) != []
  end

  defp active_rooks(board, color) do
    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.filter(&active_rook?(board, &1, color))
    |> to_alg()
  end

  defp active_rook?(board, square, color) do
    file = Square.file(square)
    rank = Square.rank(square)
    seventh = if color == :white, do: 6, else: 1

    file_open?(board, file) or semi_open?(board, file, color) or rank == seventh
  end

  defp passive_rooks(board, color) do
    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.reject(&active_rook?(board, &1, color))
    |> to_alg()
  end

  defp file_open?(board, file) do
    white = Board.piece_bb(board, :white, :pawns)
    black = Board.piece_bb(board, :black, :pawns)

    (white &&& Support.file_bb(file)) == 0 and (black &&& Support.file_bb(file)) == 0
  end

  defp semi_open?(board, file, color) do
    (Board.piece_bb(board, color, :pawns) &&& Support.file_bb(file)) == 0 and
      (Board.piece_bb(board, Board.opposite(color), :pawns) &&& Support.file_bb(file)) != 0
  end

  defp queen_activity(board, color) do
    counts = MobilityMap.available_counts(board, color)

    board
    |> Board.piece_bb(color, :queens)
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end)
  end

  defp coordination(board, color) do
    board
    |> TacticMap.pieces_squares(color)
    |> Enum.count(&(AttackMap.attackers(board, &1, color) >= 1))
  end

  defp batteries(board, color) do
    TacticMap.battery_sliders(board, color)
    |> Enum.map(fn {a, b} -> [Square.to_string(a), Square.to_string(b)] end)
  end

  defp connected_rooks?(board, color) do
    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> case do
      [a, b] ->
        (Square.file(a) == Square.file(b) or Square.rank(a) == Square.rank(b)) and
          clear_between?(board, a, b)

      _ ->
        false
    end
  end

  defp rooks_cut_off?(board, color) do
    Board.piece_bb(board, color, :rooks) |> Support.popcount() >= 2 and
      not connected_rooks?(board, color)
  end

  defp clear_between?(board, a, b) do
    step = step_size(a, b)

    (a + step)..b//step
    |> Enum.to_list()
    |> Enum.reject(&(&1 == b))
    |> Enum.all?(&(Board.piece_at(board, &1) == nil))
  end

  defp step_size(a, b) do
    df = sign(Square.file(b) - Square.file(a))
    dr = sign(Square.rank(b) - Square.rank(a))
    df + 8 * dr
  end

  defp sign(value) when value > 0, do: 1
  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 0

  defp harmony(board, color) do
    own = Board.color_occupancy(board, color)

    board
    |> TacticMap.pieces(color)
    |> Enum.reduce(0, fn {type, square}, acc ->
      acc +
        Support.popcount(
          TacticMap.piece_attacks(board, color, type, square) &&& own &&& bnot(1 <<< square)
        )
    end)
  end

  defp poorly_placed(board, color) do
    counts = MobilityMap.available_counts(board, color)

    board
    |> TacticMap.pieces_squares(color)
    |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))
    |> Enum.filter(&(Map.get(counts, &1, 0) <= 1))
    |> Enum.sort()
    |> to_alg()
  end

  defp best_worst(board, color) do
    counts = MobilityMap.available_counts(board, color)

    pieces =
      board
      |> TacticMap.pieces_squares(color)
      |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))

    case pieces do
      [] ->
        []

      pieces ->
        best = Enum.max_by(pieces, &Map.get(counts, &1, 0))
        worst = Enum.min_by(pieces, &Map.get(counts, &1, 0))
        [Square.to_string(best), Square.to_string(worst)]
    end
  end

  defp bishop_squares(board, color) do
    board
    |> Board.piece_bb(color, :bishops)
    |> Bitboard.squares()
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
