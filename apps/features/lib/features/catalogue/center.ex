defmodule Features.Catalogue.Center do
  @moduledoc """
  Spec section 6 — the centre.
  """

  import Bitwise

  alias Features.Catalogue.{AttackMap, Support}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("center.occupation", 6, [{6, "bezetting van het centrum"}], fn board ->
        key = Support.key_center_bb()

        per_color(board, fn board, color ->
          (Board.color_occupancy(board, color) &&& key)
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("center.control", 6, [{6, "controle over het centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          (AttackMap.attacked_bb(board, color) &&& center) |> Support.popcount()
        end)
      end),
      Feature.new("center.key_control", 6, [{6, "controle over d4/e4/d5/e5"}], fn board ->
        key = Support.key_center_bb()

        per_color(board, fn board, color ->
          (AttackMap.attacked_bb(board, color) &&& key) |> Support.popcount()
        end)
      end),
      Feature.new("center.extended", 6, [{6, "uitgebreid centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          (Board.piece_bb(board, color, :pawns) &&& center) |> Support.popcount()
        end)
      end),
      Feature.new("center.pawn_center", 6, [{6, "pawn center"}], fn board ->
        key = Support.key_center_bb()

        per_color(board, fn board, color ->
          (Board.piece_bb(board, color, :pawns) &&& key)
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("center.piece_center", 6, [{6, "piece center"}], fn board ->
        key = Support.key_center_bb()
        pawns = fn board, color -> Board.piece_bb(board, color, :pawns) end

        per_color(board, fn board, color ->
          (Board.color_occupancy(board, color) &&& key &&& bnot(pawns.(board, color)))
          |> Bitboard.squares()
          |> to_alg()
        end)
      end),
      Feature.new("center.stable", 6, [{6, "stabiel centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          pawns = Board.piece_bb(board, color, :pawns) &&& center
          enemy = Board.opposite(color)

          Support.popcount(pawns) >= 2 and
            Enum.all?(Bitboard.squares(pawns), fn square ->
              not Support.attacked_by_pawn?(board, square, enemy)
            end)
        end)
      end),
      Feature.new("center.mobile", 6, [{6, "mobiel centrum"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          (Board.piece_bb(board, color, :pawns) &&& center)
          |> Bitboard.squares()
          |> Enum.any?(&Support.can_advance?(board, &1))
        end)
      end),
      Feature.new("center.locked", 6, [{6, "locked center"}], fn board ->
        center = Support.center_bb()

        Enum.any?(Bitboard.squares(Board.piece_bb(board, :white, :pawns)), fn square ->
          ahead = square + 8

          (1 <<< square &&& center) != 0 and (1 <<< ahead &&& center) != 0 and
            Board.piece_at(board, ahead) == {:black, :pawns}
        end)
      end),
      Feature.new("center.open", 6, [{6, "open center"}], fn board ->
        center = Support.center_bb()
        pawns = Board.piece_bb(board, :white, :pawns) ||| Board.piece_bb(board, :black, :pawns)

        (pawns &&& center) == 0
      end),
      Feature.new("center.tension", 6, [{6, "central pawn tension"}], fn board ->
        center = Support.center_bb()
        black_pawns = Board.piece_bb(board, :black, :pawns)
        white_pawns = Board.piece_bb(board, :white, :pawns)

        white_tension =
          (Board.piece_bb(board, :white, :pawns) &&& center)
          |> Bitboard.squares()
          |> Enum.any?(&attacks_pawn?(&1, :white, black_pawns))

        black_tension =
          (Board.piece_bb(board, :black, :pawns) &&& center)
          |> Bitboard.squares()
          |> Enum.any?(&attacks_pawn?(&1, :black, white_pawns))

        white_tension or black_tension
      end),
      Feature.new("center.breakthrough", 6, [{6, "central breakthrough"}], fn board ->
        center = Support.center_bb()

        per_color(board, fn board, color ->
          enemy = Board.piece_bb(board, Board.opposite(color), :pawns)

          (Board.piece_bb(board, color, :pawns) &&& center)
          |> Bitboard.squares()
          |> Enum.any?(&break_square?(&1, color, enemy, board))
        end)
      end),
      Feature.new("center.dominance", 6, [{6, "central dominance"}], fn board ->
        center = Support.center_bb()

        white = (AttackMap.attacked_bb(board, :white) &&& center) |> Support.popcount()
        black = (AttackMap.attacked_bb(board, :black) &&& center) |> Support.popcount()

        white - black
      end)
    ]
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp attacks_pawn?(square, color, enemy) do
    file = Square.file(square)
    rank = forward_rank(Square.rank(square), color)

    Enum.any?([-1, 1], fn offset ->
      case target_square(file + offset, rank) do
        nil -> false
        target -> (1 <<< target &&& enemy) != 0
      end
    end)
  end

  defp break_square?(square, color, enemy, board) do
    file = Square.file(square)
    rank = forward_rank(Square.rank(square), color)

    case target_square(file, rank) do
      nil ->
        false

      step ->
        Board.piece_at(board, step) == nil and
          Enum.any?([-1, 1], fn offset ->
            case target_square(file + offset, forward_rank(rank, color)) do
              nil -> false
              target -> (1 <<< target &&& enemy) != 0
            end
          end)
    end
  end

  defp forward_rank(rank, :white), do: rank + 1
  defp forward_rank(rank, :black), do: rank - 1

  defp target_square(file, rank) when file in 0..7 and rank in 0..7, do: rank * 8 + file
  defp target_square(_file, _rank), do: nil

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
