defmodule Features.Catalogue.Tension do
  @moduledoc """
  Spec section 16 — structural tensions: pawn clashes, unresolved
  captures, opposed pawns, lever structures and the static-versus-
  dynamic character of the position.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @full 0xFFFFFFFFFFFFFFFF

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("tension.pawn_tension", 16, [{16, "pawn tension"}], fn board ->
        pawn_tension(board)
      end),
      Feature.new("tension.central_tension", 16, [{16, "central tension"}], fn board ->
        pawn_tension_over(board, Support.center_bb())
      end),
      Feature.new("tension.kingside_tension", 16, [{16, "kingside tension"}], fn board ->
        pawn_tension_over(board, wing_bb([5, 6, 7]))
      end),
      Feature.new("tension.queenside_tension", 16, [{16, "queenside tension"}], fn board ->
        pawn_tension_over(board, wing_bb([0, 1, 2]))
      end),
      Feature.new("tension.unresolved_captures", 16, [{16, "unresolved captures"}], fn board ->
        unresolved_captures(board)
      end),
      Feature.new(
        "tension.mutually_attacked_pieces",
        16,
        [{16, "mutually attacked pieces"}],
        fn board ->
          mutually_attacked(board)
        end
      ),
      Feature.new("tension.opposed_pawns", 16, [{16, "opposed pawns"}], fn board ->
        opposed_pawns(board)
      end),
      Feature.new("tension.possible_pawn_breaks", 16, [{16, "possible pawn breaks"}], fn board ->
        per_color(board, &possible_breaks/2)
      end),
      Feature.new("tension.lever_structure", 16, [{16, "lever structure"}], fn board ->
        per_color(board, &levers/2)
      end),
      Feature.new(
        "tension.static_versus_dynamic",
        16,
        [{16, "static versus dynamic structure"}],
        fn board ->
          %{
            "type" =>
              if(pawn_tension(board) > 0 or unresolved_captures(board) > 0,
                do: "dynamic",
                else: "static"
              )
          }
        end
      )
    ]
  end

  defp pawn_tension(board), do: pawn_tension_over(board, @full)

  defp pawn_tension_over(board, region) do
    white = pawn_targets(board, :white) &&& region
    black = pawn_targets(board, :black) &&& region
    Support.popcount(white &&& black)
  end

  defp pawn_targets(board, color) do
    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc ->
      acc ||| TacticMap.piece_attacks(board, color, :pawns, square)
    end)
  end

  defp wing_bb(files) do
    Enum.reduce(files, 0, fn file, acc -> acc ||| Support.file_bb(file) end)
  end

  defp unresolved_captures(board) do
    Enum.reduce([:white, :black], 0, fn color, acc ->
      acc + unresolved_for(board, color)
    end)
  end

  defp unresolved_for(board, color) do
    enemy = Board.opposite(color)
    our = AttackMap.attack_counts(board, color)

    (Board.color_occupancy(board, enemy) &&& bnot(Board.piece_bb(board, enemy, :kings)))
    |> Bitboard.squares()
    |> Enum.count(fn square ->
      Map.get(our, square, 0) >= 1 and AttackMap.attackers(board, square, enemy) >= 1
    end)
  end

  defp mutually_attacked(board) do
    Enum.reduce([:white, :black], 0, fn color, acc ->
      enemy = Board.opposite(color)
      enemy_occupied = Board.color_occupancy(board, enemy)

      attacks =
        board
        |> TacticMap.pieces(color)
        |> Enum.count(fn {type, square} ->
          AttackMap.attackers(board, square, enemy) >= 1 and
            (TacticMap.piece_attacks(board, color, type, square) &&& enemy_occupied) != 0
        end)

      acc + attacks
    end)
  end

  defp opposed_pawns(board) do
    white = board |> Support.pawns_by_file(:white) |> Map.keys() |> MapSet.new()
    black = board |> Support.pawns_by_file(:black) |> Map.keys() |> MapSet.new()
    MapSet.intersection(white, black) |> MapSet.size()
  end

  defp possible_breaks(board, color) do
    board
    |> Support.pawn_squares(color)
    |> Enum.filter(&pawn_break?(board, &1, color))
    |> to_alg()
  end

  defp pawn_break?(board, square, color) do
    enemy = Board.opposite(color)
    enemy_pawns = Board.piece_bb(board, enemy, :pawns)
    captures = TacticMap.piece_attacks(board, color, :pawns, square) &&& enemy_pawns
    step = Support.step(color)

    advance =
      if (square + step) in 0..63 and Board.piece_at(board, square + step) == nil do
        (TacticMap.piece_attacks(board, color, :pawns, square + step) &&& enemy_pawns) != 0
      else
        false
      end

    captures != 0 or advance
  end

  defp levers(board, color) do
    enemy = Board.opposite(color)
    enemy_pawns = Board.piece_bb(board, enemy, :pawns)

    board
    |> Support.pawn_squares(color)
    |> Enum.filter(fn square ->
      (TacticMap.piece_attacks(board, color, :pawns, square) &&& enemy_pawns)
      |> Bitboard.squares()
      |> Enum.any?(&Support.attacked_by_pawn?(board, &1, enemy))
    end)
    |> to_alg()
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
