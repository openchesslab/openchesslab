defmodule Features.Catalogue.Placement do
  @moduledoc """
  Spec section 4 — piece placement.
  """

  import Bitwise

  alias Features.Catalogue.{MobilityMap, Support}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("placement.piece_on_square", 4, [{4, "stuk op specifiek veld"}], fn board ->
        for square <- occupied_squares(board), into: %{} do
          {color, type} = Board.piece_at(board, square)
          {Square.to_string(square), Support.color_name(color) <> " " <> Support.type_name(type)}
        end
      end),
      Feature.new("placement.type_at_square", 4, [{4, "stuktype op specifiek veld"}], fn board ->
        for square <- occupied_squares(board), into: %{} do
          {_color, type} = Board.piece_at(board, square)
          {Square.to_string(square), Support.type_name(type)}
        end
      end),
      Feature.new(
        "placement.concentration.per_wing",
        4,
        [{4, "concentratie van stukken op een vleugel"}],
        fn board ->
          per_color(board, fn board, color ->
            %{
              "queenside" => non_pawn_count(board, color, 0..3),
              "kingside" => non_pawn_count(board, color, 4..7)
            }
          end)
        end
      ),
      Feature.new("placement.center", 4, [{4, "stukken in het centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          (Board.color_occupancy(board, color) &&& center) |> Support.popcount()
        end)
      end),
      Feature.new(
        "placement.enemy_territory",
        4,
        [{4, "stukken in vijandelijk gebied"}],
        fn board ->
          per_color(board, fn board, color ->
            enemy_half = Support.enemy_half_bb(color)

            (Board.color_occupancy(board, color) &&& enemy_half)
            |> Bitboard.squares()
            |> to_alg()
          end)
        end
      ),
      Feature.new("placement.advanced", 4, [{4, "advanced pieces"}], fn board ->
        per_color(board, fn board, color ->
          half = Support.enemy_half_bb(color)

          non_pawn_squares(board, color)
          |> Enum.filter(&((1 <<< &1 &&& half) != 0))
          |> to_alg()
        end)
      end),
      Feature.new("placement.centralized", 4, [{4, "centralized pieces"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          (Board.color_occupancy(board, color) &&& center)
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("placement.knight_on_rim", 4, [{4, "knight on rim"}], fn board ->
        per_color(board, fn board, color ->
          Board.piece_bb(board, color, :knights)
          |> Bitboard.squares()
          |> Enum.filter(&(Square.file(&1) in [0, 7]))
          |> to_alg()
        end)
      end),
      Feature.new("placement.knight_outpost", 4, [{4, "knight outpost"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)
          half = Support.enemy_half_bb(color)

          Board.piece_bb(board, color, :knights)
          |> Bitboard.squares()
          |> Enum.filter(fn square ->
            (1 <<< square &&& half) != 0 and
              Support.attacked_by_pawn?(board, square, color) and
              not Support.attacked_by_pawn?(board, square, enemy)
          end)
          |> to_alg()
        end)
      end),
      bishop_activity_feature("placement.bishop_active", [{4, "bishop on active diagonal"}], 8),
      bishop_activity_feature("placement.bad_bishop", [{4, "bad bishop"}], nil),
      bishop_activity_feature("placement.good_bishop", [{4, "good bishop"}], 6),
      Feature.new(
        "placement.bishop_outside_chain",
        4,
        [{4, "bishop outside pawn chain"}],
        fn board ->
          per_color(board, fn board, color ->
            own_pawns = Board.piece_bb(board, color, :pawns)

            Board.piece_bb(board, color, :bishops)
            |> Bitboard.squares()
            |> Enum.filter(fn square ->
              color_bb = Support.square_color(square) |> color_bitboard()
              count = Support.popcount(own_pawns &&& color_bb)
              count <= 2
            end)
            |> to_alg()
          end)
        end
      ),
      trapped_feature("placement.trapped_bishop", [{4, "trapped bishop"}], [:bishops]),
      trapped_feature("placement.trapped_rook", [{4, "trapped rook"}], [:rooks]),
      trapped_feature("placement.trapped_queen", [{4, "trapped queen"}], [:queens]),
      Feature.new(
        "placement.trapped_piece",
        4,
        [{4, "trapped piece in het algemeen"}],
        fn board ->
          per_color(board, fn board, color ->
            mobility = MobilityMap.piece_counts(board, color)

            non_pawn_squares(board, color)
            |> Enum.reject(&(&1 in king_squares(board, color)))
            |> Enum.filter(&(Map.get(mobility, &1, 0) == 0))
            |> to_alg()
          end)
        end
      ),
      Feature.new("placement.rook_seventh", 4, [{4, "rook on seventh rank"}], fn board ->
        per_color(board, fn board, color ->
          rank = if color == :white, do: 6, else: 1

          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.filter(&(Square.rank(&1) == rank))
          |> to_alg()
        end)
      end),
      Feature.new(
        "placement.rook_behind_passed",
        4,
        [{4, "rook behind passed pawn"}],
        fn board ->
          per_color(board, fn board, color ->
            rooks = Bitboard.squares(Board.piece_bb(board, color, :rooks))

            Enum.any?(Support.passed_pawns(board, color), fn square ->
              file = Square.file(square)
              rank = Square.rank(square)

              Enum.any?(rooks, fn rook ->
                Square.file(rook) == file and behind?(Square.rank(rook), rank, color)
              end)
            end)
          end)
        end
      ),
      Feature.new("placement.rook_open_file", 4, [{4, "rook on open file"}], fn board ->
        per_color(board, fn board, color ->
          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.filter(&open_file?(board, Square.file(&1)))
          |> to_alg()
        end)
      end),
      Feature.new("placement.rook_semi_open_file", 4, [{4, "rook on semi-open file"}], fn board ->
        per_color(board, fn board, color ->
          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.filter(&semi_open_file?(board, color, Square.file(&1)))
          |> to_alg()
        end)
      end),
      Feature.new("placement.doubled_rooks", 4, [{4, "doubled rooks"}], fn board ->
        per_color(board, fn board, color ->
          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.map(&Square.file/1)
          |> Enum.frequencies()
          |> Enum.any?(fn {_file, count} -> count >= 2 end)
        end)
      end),
      Feature.new("placement.connected_rooks", 4, [{4, "connected rooks"}], fn board ->
        occupancy = Board.occupancy(board)

        per_color(board, fn board, color ->
          rooks = Bitboard.squares(Board.piece_bb(board, color, :rooks))

          Enum.any?(rooks, fn square ->
            attacks = Features.Chess.AttackTables.rook_attacks(square, occupancy)

            Enum.any?(rooks, fn other ->
              other != square and (1 <<< other &&& attacks) != 0
            end)
          end)
        end)
      end),
      Feature.new("placement.queen_center", 4, [{4, "queen centralization"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          Board.piece_bb(board, color, :queens)
          |> Bitboard.squares()
          |> Enum.filter(&((1 <<< &1 &&& center) != 0))
          |> to_alg()
        end)
      end),
      Feature.new(
        "placement.king_center",
        4,
        [{4, "king centralization, met name in eindspelen"}],
        fn board ->
          center = Support.center_bb()

          per_color(board, fn board, color ->
            Board.piece_bb(board, color, :kings)
            |> Bitboard.squares()
            |> Enum.filter(&((1 <<< &1 &&& center) != 0))
            |> to_alg()
          end)
        end
      )
    ]
  end

  defp bishop_activity_feature(id, claim, minimum) do
    Feature.new(id, 4, claim, fn board ->
      per_color(board, fn board, color ->
        mobility = MobilityMap.piece_counts(board, color)

        Board.piece_bb(board, color, :bishops)
        |> Bitboard.squares()
        |> Enum.filter(fn square ->
          moves = Map.get(mobility, square, 0)

          if minimum == nil do
            moves <= 2
          else
            moves >= minimum
          end
        end)
        |> to_alg()
      end)
    end)
  end

  defp trapped_feature(id, claim, types) do
    Feature.new(id, 4, claim, fn board ->
      per_color(board, fn board, color ->
        mobility = MobilityMap.piece_counts(board, color)

        Enum.flat_map(types, fn type ->
          Board.piece_bb(board, color, type)
          |> Bitboard.squares()
          |> Enum.filter(&(Map.get(mobility, &1, 0) == 0))
        end)
        |> Enum.sort()
        |> to_alg()
      end)
    end)
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp occupied_squares(board) do
    0..63
    |> Enum.filter(&(Board.piece_at(board, &1) != nil))
  end

  defp non_pawn_squares(board, color) do
    (Board.color_occupancy(board, color) &&& bnot(Board.piece_bb(board, color, :pawns)))
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp non_pawn_count(board, color, files) do
    non_pawn_squares(board, color)
    |> Enum.count(&(Square.file(&1) in files))
  end

  defp king_squares(board, color), do: Bitboard.squares(Board.piece_bb(board, color, :kings))

  defp color_bitboard(:dark), do: dark_squares()
  defp color_bitboard(:light), do: bnot(dark_squares()) &&& 0xFFFFFFFFFFFFFFFF

  defp dark_squares do
    Enum.reduce(0..7, 0, fn rank, acc ->
      Enum.reduce(0..7, acc, fn file, acc ->
        if rem(file + rank, 2) == 0, do: acc ||| 1 <<< (rank * 8 + file), else: acc
      end)
    end)
  end

  defp open_file?(board, file) do
    file_mask = Support.file_bb(file)
    pawns = Board.piece_bb(board, :white, :pawns) ||| Board.piece_bb(board, :black, :pawns)

    (pawns &&& file_mask) == 0
  end

  defp semi_open_file?(board, color, file) do
    file_mask = Support.file_bb(file)
    own = Board.piece_bb(board, color, :pawns)
    enemy = Board.piece_bb(board, Board.opposite(color), :pawns)

    (own &&& file_mask) == 0 and (enemy &&& file_mask) != 0
  end

  defp behind?(rank, own, :white), do: rank < own
  defp behind?(rank, own, :black), do: rank > own

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
