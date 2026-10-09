defmodule Features.Catalogue.Goals do
  @moduledoc """
  Spec section 15 — strategic goals and plans: kingside/queenside
  operations, structural targets, piece improvements and pawn-majority
  plans. All heuristics are pinned by tests.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("goals.kingside_attack", 15, [{15, "kingside attack"}], fn board ->
        per_color(board, &kingside_attack?/2)
      end),
      Feature.new("goals.queenside_attack", 15, [{15, "queenside attack"}], fn board ->
        per_color(board, &queenside_attack?/2)
      end),
      Feature.new("goals.queenside_expansion", 15, [{15, "queenside expansion"}], fn board ->
        per_color(board, &queenside_expansion/2)
      end),
      Feature.new("goals.central_attack", 15, [{15, "central attack"}], fn board ->
        per_color(board, &central_attack?/2)
      end),
      Feature.new("goals.minority_attack", 15, [{15, "minority attack"}], fn board ->
        per_color(board, &minority_attack?/2)
      end),
      Feature.new(
        "goals.attack_isolated_pawn",
        15,
        [{15, "attack against isolated pawn"}],
        fn board ->
          per_color(board, &attack_isolated_pawn/2)
        end
      ),
      Feature.new(
        "goals.blockade_isolated_pawn",
        15,
        [{15, "blockade isolated pawn"}],
        fn board ->
          per_color(board, &blockade_isolated_pawn/2)
        end
      ),
      Feature.new("goals.attack_backward_pawn", 15, [{15, "attack backward pawn"}], fn board ->
        per_color(board, &attack_backward_pawn/2)
      end),
      Feature.new("goals.exploit_weak_square", 15, [{15, "exploit weak square"}], fn board ->
        per_color(board, &weak_squares/2)
      end),
      Feature.new("goals.establish_outpost", 15, [{15, "establish outpost"}], fn board ->
        per_color(board, &outposts/2)
      end),
      Feature.new("goals.occupy_open_file", 15, [{15, "occupy open file"}], fn board ->
        per_color(board, &open_file_rooks/2)
      end),
      Feature.new("goals.double_rooks_on_file", 15, [{15, "double rooks on file"}], fn board ->
        per_color(board, &double_rooks?/2)
      end),
      Feature.new(
        "goals.penetrate_seventh_rank",
        15,
        [{15, "penetrate seventh rank"}],
        fn board ->
          per_color(board, &seventh_rank/2)
        end
      ),
      Feature.new("goals.exchange_bad_piece", 15, [{15, "exchange bad piece"}], fn board ->
        per_color(board, &exchange_bad_piece?/2)
      end),
      Feature.new("goals.preserve_good_piece", 15, [{15, "preserve good piece"}], fn board ->
        per_color(board, &preserve_good_piece?/2)
      end),
      Feature.new("goals.trade_queens", 15, [{15, "trade queens"}], fn board ->
        per_color(board, &trade_queens?/2)
      end),
      Feature.new("goals.avoid_queen_trade", 15, [{15, "avoid queen trade"}], fn board ->
        per_color(board, &avoid_queen_trade?/2)
      end),
      Feature.new(
        "goals.improve_worst_placed_piece",
        15,
        [{15, "improve worst-placed piece"}],
        fn board ->
          per_color(board, &worst_placed/2)
        end
      ),
      Feature.new("goals.activate_king", 15, [{15, "activate king"}], fn board ->
        per_color(board, &activate_king?/2)
      end),
      Feature.new("goals.create_passed_pawn", 15, [{15, "create passed pawn"}], fn board ->
        per_color(board, &create_passed/2)
      end),
      Feature.new("goals.advance_passed_pawn", 15, [{15, "advance passed pawn"}], fn board ->
        per_color(board, &advance_passed/2)
      end),
      Feature.new("goals.blockade_passed_pawn", 15, [{15, "blockade passed pawn"}], fn board ->
        per_color(board, &blockade_passed/2)
      end),
      Feature.new("goals.pawn_break", 15, [{15, "pawn break"}], fn board ->
        per_color(board, &pawn_breaks/2)
      end),
      Feature.new("goals.pawn_storm", 15, [{15, "pawn storm"}], fn board ->
        per_color(board, &pawn_storm?/2)
      end),
      Feature.new(
        "goals.space_gaining_pawn_advance",
        15,
        [{15, "space-gaining pawn advance"}],
        fn board ->
          per_color(board, &space_gaining/2)
        end
      ),
      Feature.new(
        "goals.transfer_pieces_to_kingside",
        15,
        [{15, "transfer pieces to kingside"}],
        fn board ->
          per_color(board, &transfer_kingside?/2)
        end
      ),
      Feature.new(
        "goals.transfer_pieces_to_queenside",
        15,
        [{15, "transfer pieces to queenside"}],
        fn board ->
          per_color(board, &transfer_queenside?/2)
        end
      ),
      Feature.new("goals.rook_lift", 15, [{15, "rook lift"}], fn board ->
        per_color(board, &rook_lifts/2)
      end),
      Feature.new("goals.pressure_along_file", 15, [{15, "pressure along a file"}], fn board ->
        per_color(board, &pressure_file/2)
      end),
      Feature.new(
        "goals.pressure_along_diagonal",
        15,
        [{15, "pressure along a diagonal"}],
        fn board ->
          per_color(board, &pressure_diagonal/2)
        end
      ),
      Feature.new(
        "goals.exploit_color_complex_weakness",
        15,
        [{15, "exploit color-complex weakness"}],
        fn board ->
          per_color(board, &color_complex_weakness?/2)
        end
      )
    ]
  end

  defp kingside_attack?(board, color), do: attack_wing?(board, color, &(&1 >= 5))

  defp queenside_attack?(board, color), do: attack_wing?(board, color, &(&1 <= 2))

  defp attack_wing?(board, color, file_fun) do
    case TacticMap.king_square(board, Board.opposite(color)) do
      nil -> false
      king -> file_fun.(Square.file(king)) and ring_attack_count(board, color) >= 3
    end
  end

  defp queenside_expansion(board, color) do
    board
    |> Support.pawn_squares(color)
    |> Enum.filter(fn square -> Square.file(square) <= 2 and advanced?(board, square) end)
    |> to_alg()
  end

  defp advanced?(board, square) do
    {color, :pawns} = Board.piece_at(board, square)

    if color == :white, do: Square.rank(square) >= 3, else: Square.rank(square) <= 4
  end

  defp central_attack?(board, color) do
    counts = AttackMap.attack_counts(board, color)

    Support.key_center_bb()
    |> Bitboard.squares()
    |> Enum.reduce(0, fn square, acc -> acc + Map.get(counts, square, 0) end) >= 2
  end

  defp minority_attack?(board, color) do
    enemy = Board.opposite(color)
    we = queenside_pawns(board, color)
    them = queenside_pawns(board, enemy)
    them >= 4 and we >= 1 and we < them
  end

  defp queenside_pawns(board, color) do
    board
    |> Support.pawn_squares(color)
    |> Enum.count(&(Square.file(&1) <= 2))
  end

  defp attack_isolated_pawn(board, color) do
    board
    |> Support.isolated_pawns(Board.opposite(color))
    |> to_alg()
  end

  defp blockade_isolated_pawn(board, color) do
    step = Support.step(color)

    board
    |> Support.isolated_pawns(Board.opposite(color))
    |> Enum.map(&(&1 + step))
    |> Enum.filter(&(&1 in 0..63))
    |> to_alg()
  end

  defp attack_backward_pawn(board, color) do
    board
    |> Support.backward_pawns(Board.opposite(color))
    |> to_alg()
  end

  defp weak_squares(board, color) do
    enemy = Board.opposite(color)

    (Support.enemy_half_bb(color) &&& bnot(Board.occupancy(board)))
    |> Bitboard.squares()
    |> Enum.filter(fn square ->
      Support.attacked_by_pawn?(board, square, color) and
        not Support.attacked_by_pawn?(board, square, enemy)
    end)
    |> Enum.sort()
    |> to_alg()
  end

  defp outposts(board, color) do
    enemy = Board.opposite(color)
    half = Support.enemy_half_bb(color)

    [:knights, :bishops]
    |> Enum.flat_map(fn type ->
      (Board.piece_bb(board, color, type) &&& half)
      |> Bitboard.squares()
      |> Enum.filter(fn square ->
        Support.attacked_by_pawn?(board, square, color) and
          not Support.attacked_by_pawn?(board, square, enemy)
      end)
    end)
    |> Enum.sort()
    |> to_alg()
  end

  defp open_file_rooks(board, color) do
    open = open_files(board)

    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.filter(&MapSet.member?(open, Square.file(&1)))
    |> to_alg()
  end

  defp open_files(board) do
    white = Board.piece_bb(board, :white, :pawns)
    black = Board.piece_bb(board, :black, :pawns)

    for file <- 0..7,
        (white &&& Support.file_bb(file)) == 0 and (black &&& Support.file_bb(file)) == 0,
        into: MapSet.new(),
        do: file
  end

  defp double_rooks?(board, color) do
    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.frequencies_by(&Square.file/1)
    |> Enum.any?(fn {_file, count} -> count >= 2 end)
  end

  defp seventh_rank(board, color) do
    rank = if color == :white, do: 6, else: 1

    ((Board.piece_bb(board, color, :rooks) ||| Board.piece_bb(board, color, :queens)) &&&
       Support.rank_bb(rank))
    |> Bitboard.squares()
    |> to_alg()
  end

  defp exchange_bad_piece?(board, color) do
    bad_bishop?(board, color) and not bad_bishop?(board, Board.opposite(color))
  end

  defp preserve_good_piece?(board, color) do
    good_bishop?(board, color) and not good_bishop?(board, Board.opposite(color))
  end

  defp bad_bishop?(board, color) do
    board
    |> bishop_squares(color)
    |> Enum.any?(&(Support.bishop_pawn_conflict(board, &1) >= 5))
  end

  defp good_bishop?(board, color) do
    board
    |> bishop_squares(color)
    |> Enum.any?(&(Support.bishop_pawn_conflict(board, &1) <= 2))
  end

  defp bishop_squares(board, color) do
    board
    |> Board.piece_bb(color, :bishops)
    |> Bitboard.squares()
  end

  defp trade_queens?(board, color) do
    enemy = Board.opposite(color)

    queens?(board) and
      Support.material_value(board, color) - Support.material_value(board, enemy) >= 2
  end

  defp avoid_queen_trade?(board, color) do
    enemy = Board.opposite(color)

    queens?(board) and
      Support.material_value(board, color) - Support.material_value(board, enemy) <= -2
  end

  defp worst_placed(board, color) do
    counts = MobilityMap.available_counts(board, color)

    board
    |> TacticMap.pieces_squares(color)
    |> Enum.reject(&(Board.piece_at(board, &1) == {color, :kings}))
    |> Enum.filter(&(Map.get(counts, &1, 0) <= 2))
    |> Enum.sort()
    |> to_alg()
  end

  defp activate_king?(board, color) do
    not queens?(board) and king_on_back_rank?(board, color)
  end

  defp king_on_back_rank?(board, color) do
    case TacticMap.king_square(board, color) do
      nil -> false
      king -> Square.rank(king) == back_rank(color)
    end
  end

  defp back_rank(:white), do: 0
  defp back_rank(:black), do: 7

  defp create_passed(board, color) do
    enemy = Board.opposite(color)
    enemy_files = board |> Support.pawns_by_file(enemy) |> Map.keys() |> MapSet.new()
    passed = board |> Support.passed_pawns(color) |> MapSet.new()

    board
    |> Support.pawn_squares(color)
    |> Enum.filter(fn square ->
      file = Square.file(square)

      not MapSet.member?(enemy_files, file) and not MapSet.member?(passed, square)
    end)
    |> to_alg()
  end

  defp advance_passed(board, color) do
    board
    |> Support.passed_pawns(color)
    |> to_alg()
  end

  defp blockade_passed(board, color) do
    board
    |> Support.passed_pawns(Board.opposite(color))
    |> to_alg()
  end

  defp pawn_breaks(board, color) do
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

  defp pawn_storm?(board, color) do
    case TacticMap.king_square(board, Board.opposite(color)) do
      nil ->
        false

      king ->
        files = wing(Square.file(king))

        board
        |> Support.pawn_squares(color)
        |> Enum.count(fn square ->
          Square.file(square) in files and storm_rank?(board, square)
        end) >= 3
    end
  end

  defp storm_rank?(board, square) do
    {color, :pawns} = Board.piece_at(board, square)

    if color == :white, do: Square.rank(square) >= 4, else: Square.rank(square) <= 3
  end

  defp wing(file) when file >= 5, do: [5, 6, 7]
  defp wing(file) when file <= 2, do: [0, 1, 2]
  defp wing(_file), do: [0, 1, 2, 5, 6, 7]

  defp space_gaining(board, color) do
    board
    |> Support.pawn_squares(color)
    |> Enum.filter(&in_enemy_half?(board, &1))
    |> Enum.reject(&promotion_rank?(board, &1))
    |> to_alg()
  end

  defp in_enemy_half?(board, square) do
    {color, :pawns} = Board.piece_at(board, square)

    if color == :white, do: Square.rank(square) >= 4, else: Square.rank(square) <= 3
  end

  defp promotion_rank?(board, square) do
    {color, :pawns} = Board.piece_at(board, square)

    if color == :white, do: Square.rank(square) == 6, else: Square.rank(square) == 1
  end

  defp transfer_kingside?(board, color) do
    enemy_king_wing?(board, color, &(&1 >= 5)) and
      pieces_on_files(board, color, [5, 6, 7]) >= 2
  end

  defp transfer_queenside?(board, color) do
    enemy_king_wing?(board, color, &(&1 <= 2)) and
      pieces_on_files(board, color, [0, 1, 2]) >= 2
  end

  defp enemy_king_wing?(board, color, file_fun) do
    case TacticMap.king_square(board, Board.opposite(color)) do
      nil -> false
      king -> file_fun.(Square.file(king))
    end
  end

  defp pieces_on_files(board, color, files) do
    [:knights, :bishops, :queens]
    |> Enum.flat_map(&(board |> Board.piece_bb(color, &1) |> Bitboard.squares()))
    |> Enum.count(&(Square.file(&1) in files))
  end

  defp rook_lifts(board, color) do
    ranks = if color == :white, do: MapSet.new([2, 3]), else: MapSet.new([4, 5])

    board
    |> Board.piece_bb(color, :rooks)
    |> Bitboard.squares()
    |> Enum.filter(&MapSet.member?(ranks, Square.rank(&1)))
    |> to_alg()
  end

  defp pressure_file(board, color) do
    pressure(board, color, [:rooks, :queens], &aligned_file?/2)
  end

  defp pressure_diagonal(board, color) do
    pressure(board, color, [:bishops, :queens], &aligned_diagonal?/2)
  end

  defp pressure(board, color, types, align_fun) do
    enemy_pieces =
      board
      |> TacticMap.enemy_piece_bb(color)
      |> Bitboard.squares()

    types
    |> Enum.flat_map(fn type -> board |> Board.piece_bb(color, type) |> Bitboard.squares() end)
    |> Enum.filter(&align_fun.(&1, enemy_pieces))
    |> Enum.sort()
    |> to_alg()
  end

  defp aligned_file?(square, enemy_pieces) do
    Enum.any?(enemy_pieces, &(Square.file(&1) == Square.file(square)))
  end

  defp aligned_diagonal?(square, enemy_pieces) do
    Enum.any?(enemy_pieces, fn target ->
      abs(Square.file(target) - Square.file(square)) ==
        abs(Square.rank(target) - Square.rank(square))
    end)
  end

  defp color_complex_weakness?(board, color) do
    enemy = Board.opposite(color)

    case TacticMap.king_square(board, enemy) do
      nil ->
        false

      king ->
        king_color = Support.square_color(king)
        bishop_colors = Support.bishop_colors(board, enemy)
        not MapSet.member?(bishop_colors, king_color)
    end
  end

  defp queens?(board) do
    Support.popcount(Board.piece_bb(board, :white, :queens)) >= 1 and
      Support.popcount(Board.piece_bb(board, :black, :queens)) >= 1
  end

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

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
