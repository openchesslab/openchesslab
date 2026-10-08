defmodule Features.Catalogue.Material do
  @moduledoc """
  Spec section 2 — material.
  """

  alias Features.Catalogue.Support
  alias Features.Chess.Board
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    count_features() ++
      [
        Feature.new("material.total_value", 2, [{2, "totale materiaalwaarde"}], fn board ->
          %{
            "white" => Support.material_value(board, :white),
            "black" => Support.material_value(board, :black)
          }
        end),
        Feature.new("material.difference", 2, [{2, "materiaalverschil"}], fn board ->
          Support.material_value(board, :white) - Support.material_value(board, :black)
        end),
        Feature.new(
          "material.value_ratio.per_type",
          2,
          [{2, "materiaalverhouding per stuktype"}],
          fn board ->
            for type <- [:pawn, :knight, :bishop, :rook, :queen], into: %{} do
              {to_string(type), share(board, plural(type))}
            end
          end
        ),
        Feature.new("material.bishop_pair", 2, [{2, "loperpaar"}], fn board ->
          %{
            "white" => Support.piece_count(board, :white, :bishops) >= 2,
            "black" => Support.piece_count(board, :black, :bishops) >= 2
          }
        end),
        Feature.new("material.bishop_pair.both", 2, [{2, "beide partijen loperpaar"}], fn board ->
          Support.piece_count(board, :white, :bishops) >= 2 and
            Support.piece_count(board, :black, :bishops) >= 2
        end),
        Feature.new(
          "material.imbalance.knight_vs_bishop",
          2,
          [{2, "paard tegen loper"}],
          fn board ->
            opposing?(
              piece_count(board, :white, :knights) - piece_count(board, :black, :knights),
              piece_count(board, :white, :bishops) - piece_count(board, :black, :bishops)
            )
          end
        ),
        Feature.new(
          "material.imbalance.rook_vs_minor",
          2,
          [{2, "toren tegen lichte stukken"}],
          fn board ->
            opposing?(
              piece_count(board, :white, :rooks) - piece_count(board, :black, :rooks),
              Support.minor_count(board, :white) - Support.minor_count(board, :black)
            )
          end
        ),
        Feature.new(
          "material.imbalance.queen_vs_rooks",
          2,
          [{2, "dame tegen torens"}],
          fn board ->
            opposing?(
              piece_count(board, :white, :queens) - piece_count(board, :black, :queens),
              piece_count(board, :white, :rooks) - piece_count(board, :black, :rooks)
            )
          end
        ),
        Feature.new(
          "material.imbalance.two_rooks_vs_queen",
          2,
          [{2, "twee torens tegen dame"}],
          fn board ->
            rook_diff = piece_count(board, :white, :rooks) - piece_count(board, :black, :rooks)
            queen_diff = piece_count(board, :white, :queens) - piece_count(board, :black, :queens)

            (rook_diff >= 2 and queen_diff <= -1) or (rook_diff <= -2 and queen_diff >= 1)
          end
        ),
        Feature.new(
          "material.exchange_advantage",
          2,
          [{2, "exchange advantage / exchange sacrifice"}],
          fn board ->
            %{
              "white" => up_exchange?(board, :white),
              "black" => up_exchange?(board, :black)
            }
          end
        ),
        Feature.new("material.imbalanced", 2, [{2, "ongelijke materiaalbalans"}], fn board ->
          Support.material_value(board, :white) != Support.material_value(board, :black) or
            Enum.any?(Board.types(), fn type ->
              piece_count(board, :white, type) != piece_count(board, :black, type)
            end)
        end),
        Feature.new(
          "material.bishops.opposite_color",
          2,
          [{2, "opposite-colored bishops"}],
          fn board ->
            white = Support.bishop_colors(board, :white)
            black = Support.bishop_colors(board, :black)

            MapSet.size(white) > 0 and MapSet.size(black) > 0 and
              MapSet.disjoint?(white, black)
          end
        ),
        Feature.new("material.bishops.same_color", 2, [{2, "same-colored bishops"}], fn board ->
          white = Support.bishop_colors(board, :white)
          black = Support.bishop_colors(board, :black)

          MapSet.size(white) > 0 and MapSet.size(black) > 0 and
            not MapSet.disjoint?(white, black)
        end),
        Feature.new(
          "material.queenless",
          2,
          [{2, "queenless middlegame / queens afwezig"}],
          fn board ->
            piece_count(board, :white, :queens) == 0 and piece_count(board, :black, :queens) == 0
          end
        ),
        Feature.new(
          "material.endgame_transition",
          2,
          [{2, "overgang naar eindspelmateriaal"}],
          fn board ->
            piece_count(board, :white, :queens) == 0 and piece_count(board, :black, :queens) == 0 and
              Support.minor_count(board, :white) + piece_count(board, :white, :rooks) +
                Support.minor_count(board, :black) + piece_count(board, :black, :rooks) <= 6
          end
        )
      ]
  end

  defp count_features do
    for {id, type} <- [
          {"material.count.queen", :queens},
          {"material.count.rook", :rooks},
          {"material.count.bishop", :bishops},
          {"material.count.knight", :knights},
          {"material.count.pawn", :pawns}
        ] do
      bullet = plural_bullet(Support.type_name(type))

      Feature.new(id, 2, [{2, bullet}], fn board ->
        %{
          "white" => piece_count(board, :white, type),
          "black" => piece_count(board, :black, type)
        }
      end)
    end
  end

  defp plural_bullet("pawn"), do: "aantal pionnen"
  defp plural_bullet("knight"), do: "aantal paarden"
  defp plural_bullet("bishop"), do: "aantal lopers"
  defp plural_bullet("rook"), do: "aantal torens"
  defp plural_bullet("queen"), do: "aantal dames"

  defp plural(:pawn), do: :pawns
  defp plural(:knight), do: :knights
  defp plural(:bishop), do: :bishops
  defp plural(:rook), do: :rooks
  defp plural(:queen), do: :queens

  defp share(board, type) do
    white = piece_count(board, :white, type)
    black = piece_count(board, :black, type)

    case white + black do
      0 -> nil
      total -> white / total
    end
  end

  defp piece_count(board, color, type), do: Support.piece_count(board, color, type)

  defp opposing?(diff_a, diff_b), do: (diff_a > 0 and diff_b < 0) or (diff_a < 0 and diff_b > 0)

  defp up_exchange?(board, color) do
    enemy = Board.opposite(color)

    piece_count(board, color, :rooks) == piece_count(board, enemy, :rooks) + 1 and
      Support.minor_count(board, color) == Support.minor_count(board, enemy) - 1 and
      piece_count(board, color, :queens) == piece_count(board, enemy, :queens) and
      piece_count(board, color, :pawns) == piece_count(board, enemy, :pawns)
  end
end
