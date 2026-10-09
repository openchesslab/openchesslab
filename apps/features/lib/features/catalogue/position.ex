defmodule Features.Catalogue.Position do
  @moduledoc """
  Spec section 19 — position type: open/semi-open/closed and locked
  structures, tactical-quiet-sharp-maneuvering character, symmetry,
  opposite-side castling and the amount of material left on the board.
  """

  import Bitwise

  alias Features.Catalogue.{Support, TacticMap}
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("position.open_position", 19, [{19, "open position"}], fn board ->
        file_kind_count(board, :open) >= 3
      end),
      Feature.new("position.semi_open_position", 19, [{19, "semi-open position"}], fn board ->
        file_kind_count(board, :open) < 3 and file_kind_count(board, :semi_open) >= 1
      end),
      Feature.new("position.closed_position", 19, [{19, "closed position"}], fn board ->
        file_kind_count(board, :open) == 0 and file_kind_count(board, :semi_open) <= 1
      end),
      Feature.new("position.locked_position", 19, [{19, "locked position"}], fn board ->
        blocked_pawns(board) >= 10
      end),
      Feature.new("position.tactical_position", 19, [{19, "tactical position"}], fn board ->
        tactical?(board)
      end),
      Feature.new("position.quiet_position", 19, [{19, "quiet position"}], fn board ->
        quiet?(board)
      end),
      Feature.new("position.sharp_position", 19, [{19, "sharp position"}], fn board ->
        sharp?(board)
      end),
      Feature.new("position.maneuvering_position", 19, [{19, "maneuvering position"}], fn board ->
        maneuvering?(board)
      end),
      Feature.new("position.symmetric_position", 19, [{19, "symmetric position"}], fn board ->
        symmetric?(board)
      end),
      Feature.new("position.asymmetric_position", 19, [{19, "asymmetric position"}], fn board ->
        not symmetric?(board)
      end),
      Feature.new(
        "position.opposite_side_castling_position",
        19,
        [{19, "opposite-side castling position"}],
        fn board ->
          opposite_side_castling?(board)
        end
      ),
      Feature.new("position.queenless_middlegame", 19, [{19, "queenless middlegame"}], fn board ->
        queenless_middlegame?(board)
      end),
      Feature.new(
        "position.endgame_like_position",
        19,
        [{19, "endgame-like position"}],
        fn board ->
          endgame_like?(board)
        end
      ),
      Feature.new(
        "position.material_imbalanced_position",
        19,
        [{19, "material-imbalanced position"}],
        fn board ->
          material_imbalanced?(board)
        end
      )
    ]
  end

  defp file_kind_count(board, kind) do
    Enum.count(0..7, &(file_kind(board, &1) == kind))
  end

  defp file_kind(board, file) do
    white = Support.popcount(Board.piece_bb(board, :white, :pawns) &&& Support.file_bb(file))
    black = Support.popcount(Board.piece_bb(board, :black, :pawns) &&& Support.file_bb(file))

    cond do
      white == 0 and black == 0 -> :open
      white > 0 and black > 0 -> :closed
      true -> :semi_open
    end
  end

  defp blocked_pawns(board) do
    Enum.reduce([:white, :black], 0, fn color, acc ->
      step = Support.step(color)
      enemy = Board.opposite(color)

      acc +
        Enum.count(Support.pawn_squares(board, color), fn square ->
          target = square + step
          target in 0..63 and Board.piece_at(board, target) == {enemy, :pawns}
        end)
    end)
  end

  defp tactical?(board) do
    pawn_clash = pawn_tension(board)

    forcing =
      Enum.reduce([:white, :black], 0, fn color, acc ->
        acc + length(TacticMap.checks(board, color)) + length(TacticMap.captures(board, color))
      end)

    pawn_clash >= 2 or forcing >= 3
  end

  defp quiet?(board) do
    Enum.all?([:white, :black], fn color ->
      TacticMap.checks(board, color) == [] and TacticMap.captures(board, color) == []
    end) and pawn_tension(board) == 0
  end

  defp pawn_tension(board) do
    white = pawn_targets(board, :white)
    black = pawn_targets(board, :black)
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

  defp sharp?(board) do
    queens?(board) and pawn_tension(board) > 0 and
      Enum.all?([:white, :black], &weak_shelter?(board, &1))
  end

  defp weak_shelter?(board, color) do
    case TacticMap.king_square(board, color) do
      nil ->
        false

      king ->
        king_file = Square.file(king)
        own_pawns = Board.piece_bb(board, color, :pawns)

        [king_file - 1, king_file, king_file + 1]
        |> Enum.filter(&(&1 in 0..7))
        |> Enum.count(fn file -> (own_pawns &&& Support.file_bb(file)) != 0 end) <= 1
    end
  end

  defp maneuvering?(board) do
    file_kind_count(board, :open) <= 1 and pawn_tension(board) == 0 and queens?(board)
  end

  defp symmetric?(board) do
    mirror = fn file, rank -> (7 - rank) * 8 + file end

    white_set =
      board
      |> TacticMap.pieces(:white)
      |> MapSet.new()

    black_set =
      board
      |> TacticMap.pieces(:black)
      |> MapSet.new(fn {type, square} ->
        {type, mirror.(Square.file(square), Square.rank(square))}
      end)

    MapSet.equal?(white_set, black_set)
  end

  defp opposite_side_castling?(board) do
    case {castled_side(board, :white), castled_side(board, :black)} do
      {:kingside, :queenside} -> true
      {:queenside, :kingside} -> true
      _ -> false
    end
  end

  defp castled_side(board, color) do
    case TacticMap.king_square(board, color) do
      square when square in [2, 58] -> :queenside
      square when square in [6, 62] -> :kingside
      _ -> nil
    end
  end

  defp queenless_middlegame?(board) do
    not queens?(board) and
      Enum.all?([:white, :black], fn color ->
        Support.minor_count(board, color) + Support.piece_count(board, color, :rooks) >= 3
      end)
  end

  defp endgame_like?(board) do
    not queens?(board) and
      Support.material_value(board, :white) + Support.material_value(board, :black) <= 14
  end

  defp material_imbalanced?(board) do
    abs(Support.material_value(board, :white) - Support.material_value(board, :black)) >= 2
  end

  defp queens?(board) do
    Support.popcount(Board.piece_bb(board, :white, :queens)) >= 1 and
      Support.popcount(Board.piece_bb(board, :black, :queens)) >= 1
  end
end
