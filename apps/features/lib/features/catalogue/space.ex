defmodule Features.Catalogue.Space do
  @moduledoc """
  Spec section 7 — space and territory.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, MobilityMap, Support}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("space.total", 7, [{7, "totale space advantage"}], fn board ->
        space(board, :white, 0xFFFFFFFFFFFFFFFF) - space(board, :black, 0xFFFFFFFFFFFFFFFF)
      end),
      Feature.new("space.kingside", 7, [{7, "ruimte op kingside"}], fn board ->
        files = wing_mask(4..7)
        space(board, :white, files) - space(board, :black, files)
      end),
      Feature.new("space.queenside", 7, [{7, "ruimte op queenside"}], fn board ->
        files = wing_mask(0..3)
        space(board, :white, files) - space(board, :black, files)
      end),
      Feature.new("space.center", 7, [{7, "ruimte in het centrum"}], fn board ->
        center = Support.center_bb()
        space(board, :white, center) - space(board, :black, center)
      end),
      Feature.new(
        "space.enemy_half_control",
        7,
        [{7, "aantal gecontroleerde velden in vijandelijke helft"}],
        fn board ->
          per_color(board, fn board, color -> space(board, color, 0xFFFFFFFFFFFFFFFF) end)
        end
      ),
      Feature.new("space.territory", 7, [{7, "territory advantage"}], fn board ->
        per_color(board, fn board, color ->
          half = Support.enemy_half_bb(color)
          enemy_attacks = AttackMap.attacked_bb(board, Board.opposite(color))

          (AttackMap.attacked_bb(board, color) &&& half &&& bnot(enemy_attacks))
          |> Support.popcount()
        end)
      end),
      Feature.new("space.cramping", 7, [{7, "cramping van de tegenstander"}], fn board ->
        white = MobilityMap.total(board, :white)
        black = MobilityMap.total(board, :black)

        %{
          "white" => black <= white - 10,
          "black" => white <= black - 10
        }
      end),
      Feature.new(
        "space.advanced_chain",
        7,
        [{7, "advanced pawn chain die ruimte wint"}],
        fn board ->
          per_color(board, fn board, color ->
            board
            |> advanced_pawns(color)
            |> Enum.any?(fn square ->
              file = Square.file(square)

              Enum.any?([-1, 1], fn offset ->
                board |> advanced_pawns(color) |> Enum.member?(square + offset) and
                  Square.file(square + offset) == file + offset
              end)
            end)
          end)
        end
      ),
      Feature.new("space.gaining_push", 7, [{7, "space-gaining pawn push"}], fn board ->
        per_color(board, fn board, color ->
          enemy_attacks = AttackMap.attacked_bb(board, Board.opposite(color))

          Board.piece_bb(board, color, :pawns)
          |> Bitboard.squares()
          |> Enum.any?(fn square ->
            file = Square.file(square)
            rank = forward_rank(Square.rank(square), color)

            case target_square(file, rank) do
              nil ->
                false

              step ->
                Board.piece_at(board, step) == nil and (1 <<< step &&& enemy_attacks) == 0
            end
          end)
        end)
      end)
    ]
  end

  defp space(board, color, mask) do
    (AttackMap.attacked_bb(board, color) &&& Support.enemy_half_bb(color) &&& mask)
    |> Support.popcount()
  end

  defp wing_mask(files) do
    Enum.reduce(files, 0, fn file, mask -> mask ||| Support.file_bb(file) end)
  end

  defp advanced_pawns(board, color) do
    half = Support.enemy_half_bb(color)

    (Board.piece_bb(board, color, :pawns) &&& half)
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp forward_rank(rank, :white), do: rank + 1
  defp forward_rank(rank, :black), do: rank - 1

  defp target_square(file, rank) when file in 0..7 and rank in 0..7, do: rank * 8 + file
  defp target_square(_file, _rank), do: nil

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end
end
