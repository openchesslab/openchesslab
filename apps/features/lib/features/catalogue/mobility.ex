defmodule Features.Catalogue.Mobility do
  @moduledoc """
  Spec section 5 — mobility and activity.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @original_minor_files [1, 2, 5, 6]

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("mobility.total", 5, [{5, "totale mobiliteit"}], fn board ->
        MobilityMap.total(board, :white) + MobilityMap.total(board, :black)
      end),
      Feature.new("mobility.per_side", 5, [{5, "mobiliteit per partij"}], fn board ->
        %{
          "white" => MobilityMap.total(board, :white),
          "black" => MobilityMap.total(board, :black)
        }
      end),
      Feature.new("mobility.per_piece", 5, [{5, "mobiliteit per stuk"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> MobilityMap.piece_counts(color)
          |> Map.new(fn {square, count} -> {Square.to_string(square), count} end)
        end)
      end),
      Feature.new("mobility.legal_moves", 5, [{5, "aantal legale zetten"}], fn board ->
        MobilityMap.legal_count(board)
      end),
      Feature.new(
        "mobility.available_squares",
        5,
        [{5, "aantal beschikbare velden per stuk"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> MobilityMap.available_counts(color)
            |> Map.new(fn {square, count} -> {Square.to_string(square), count} end)
          end)
        end
      ),
      Feature.new("mobility.restricted", 5, [{5, "restricted piece"}], fn board ->
        per_color(board, fn board, color ->
          mobility = MobilityMap.piece_counts(board, color)

          active_piece_squares(board, color)
          |> Enum.filter(&(Map.get(mobility, &1, 0) <= 1))
          |> to_alg()
        end)
      end),
      Feature.new("mobility.trapped_piece", 5, [{5, "trapped piece"}], fn board ->
        per_color(board, fn board, color ->
          mobility = MobilityMap.piece_counts(board, color)

          all_piece_squares(board, color)
          |> Enum.filter(&(Map.get(mobility, &1, 0) == 0))
          |> to_alg()
        end)
      end),
      Feature.new(
        "mobility.active_passive",
        5,
        [{5, "actieve versus passieve stukken"}],
        fn board ->
          per_color(board, fn board, color ->
            mobility = MobilityMap.piece_counts(board, color)

            counts =
              active_piece_squares(board, color)
              |> Enum.map(&Map.get(mobility, &1, 0))

            %{
              "active" => Enum.count(counts, &(&1 >= 4)),
              "passive" => Enum.count(counts, &(&1 <= 1))
            }
          end)
        end
      ),
      activity_feature("mobility.rook_activity", [{5, "rook activity"}], :rooks),
      activity_feature("mobility.bishop_activity", [{5, "bishop activity"}], :bishops),
      activity_feature("mobility.queen_activity", [{5, "queen activity"}], :queens),
      activity_feature("mobility.knight_activity", [{5, "knight activity"}], :knights),
      activity_feature("mobility.king_activity", [{5, "king activity"}], :kings),
      Feature.new("mobility.development", 5, [{5, "development"}], fn board ->
        per_color(board, &developed/2)
      end),
      Feature.new(
        "mobility.development_advantage",
        5,
        [{5, "ontwikkelingsvoorsprong"}],
        fn board ->
          developed(board, :white) - developed(board, :black)
        end
      ),
      Feature.new("mobility.undeveloped", 5, [{5, "undeveloped pieces"}], fn board ->
        per_color(board, fn board, color -> to_alg(undeveloped_squares(board, color)) end)
      end),
      Feature.new(
        "mobility.development_deficit",
        5,
        [{5, "tempi / development deficit"}],
        fn board ->
          per_color(board, fn board, color ->
            king_on_original =
              board
              |> Board.piece_bb(color, :kings)
              |> Bitboard.squares()
              |> Enum.any?(fn square ->
                Square.rank(square) == original_back_rank(color) and Square.file(square) == 4
              end)

            length(undeveloped_squares(board, color)) + if(king_on_original, do: 1, else: 0)
          end)
        end
      ),
      Feature.new("mobility.coordination", 5, [{5, "piece coordination"}], fn board ->
        per_color(board, fn board, color ->
          defenders = AttackMap.defender_counts(board, color)

          active_piece_squares(board, color)
          |> Enum.count(&Map.has_key?(defenders, &1))
        end)
      end),
      Feature.new(
        "mobility.uncoordinated",
        5,
        [{5, "slecht gecoördineerde stukken"}],
        fn board ->
          per_color(board, fn board, color ->
            defenders = AttackMap.defender_counts(board, color)

            active_piece_squares(board, color)
            |> Enum.reject(&Map.has_key?(defenders, &1))
            |> to_alg()
          end)
        end
      )
    ]
  end

  defp activity_feature(id, claim, type) do
    Feature.new(id, 5, claim, fn board ->
      per_color(board, fn board, color ->
        board
        |> MobilityMap.piece_counts(color)
        |> then(fn counts ->
          board
          |> Board.piece_bb(color, type)
          |> Bitboard.squares()
          |> Enum.map(&Map.get(counts, &1, 0))
          |> Enum.sum()
        end)
      end)
    end)
  end

  defp undeveloped_squares(board, color) do
    back = original_back_rank(color)

    squares =
      for type <- [:knights, :bishops],
          square <- Bitboard.squares(Board.piece_bb(board, color, type)),
          Square.rank(square) == back and Square.file(square) in @original_minor_files,
          do: square

    Enum.sort(squares)
  end

  defp developed(board, color), do: 4 - length(undeveloped_squares(board, color))

  defp original_back_rank(:white), do: 0
  defp original_back_rank(:black), do: 7

  defp active_piece_squares(board, color) do
    (Board.color_occupancy(board, color) &&&
       bnot(Board.piece_bb(board, color, :pawns) ||| Board.piece_bb(board, color, :kings)))
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp all_piece_squares(board, color) do
    Board.color_occupancy(board, color)
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
