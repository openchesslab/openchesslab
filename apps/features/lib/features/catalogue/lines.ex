defmodule Features.Catalogue.Lines do
  @moduledoc """
  Spec section 9 — open lines and batteries.
  """

  import Bitwise

  alias Features.Catalogue.Support
  alias Features.Chess.{AttackTables, Bitboard, Board, Square}
  alias Features.Feature

  @heavy [:rooks, :queens]
  @diagonal_types [:bishops, :queens]

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("lines.open_files", 9, [{9, "open file"}], fn board ->
        pawn_files = pawn_files(board)

        0..7
        |> Enum.filter(&(Enum.member?(pawn_files, &1) == false))
        |> Enum.map(&Support.file_letter/1)
      end),
      Feature.new("lines.semi_open_files", 9, [{9, "semi-open file"}], fn board ->
        per_color(board, fn board, color ->
          own = own_pawn_files(board, color)
          enemy = own_pawn_files(board, Board.opposite(color))

          0..7
          |> Enum.filter(&(not Enum.member?(own, &1) and Enum.member?(enemy, &1)))
          |> Enum.map(&Support.file_letter/1)
        end)
      end),
      Feature.new("lines.closed_files", 9, [{9, "closed file"}], fn board ->
        white = own_pawn_files(board, :white)
        black = own_pawn_files(board, :black)

        0..7
        |> Enum.filter(&(Enum.member?(white, &1) and Enum.member?(black, &1)))
        |> Enum.map(&Support.file_letter/1)
      end),
      Feature.new("lines.open_diagonals", 9, [{9, "open diagonal"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)

          diagonals()
          |> Enum.filter(fn {_family, _key, squares} ->
            bits =
              squares
              |> Enum.map(&(1 <<< &1))
              |> Enum.reduce(0, fn left, right -> left ||| right end)

            (bits &&& own) == 0
          end)
          |> Enum.map(&label/1)
        end)
      end),
      Feature.new("lines.semi_open_diagonals", 9, [{9, "semi-open diagonal"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)
          enemy = Board.piece_bb(board, Board.opposite(color), :pawns)

          diagonals()
          |> Enum.filter(fn {_family, _key, squares} ->
            bits =
              squares
              |> Enum.map(&(1 <<< &1))
              |> Enum.reduce(0, fn left, right -> left ||| right end)

            (bits &&& own) == 0 and (bits &&& enemy) != 0
          end)
          |> Enum.map(&label/1)
        end)
      end),
      Feature.new("lines.long_diagonals", 9, [{9, "lange diagonalen"}], fn board ->
        per_color(board, fn board, color ->
          own = Board.piece_bb(board, color, :pawns)

          diagonals()
          |> Enum.filter(fn {_family, _key, squares} ->
            bits =
              squares
              |> Enum.map(&(1 <<< &1))
              |> Enum.reduce(0, fn left, right -> left ||| right end)

            length(squares) >= 5 and (bits &&& own) == 0
          end)
          |> Enum.map(&label/1)
        end)
      end),
      Feature.new("lines.open_ranks", 9, [{9, "open rank"}], fn board ->
        pawns =
          Board.piece_bb(board, :white, :pawns) ||| Board.piece_bb(board, :black, :pawns)

        0..7
        |> Enum.filter(fn rank -> (pawns &&& Support.rank_bb(rank)) == 0 end)
        |> Enum.map(&(&1 + 1))
      end),
      Feature.new("lines.rook_open_file", 9, [{9, "rook op open file"}], fn board ->
        per_color(board, fn board, color ->
          pawns = all_pawns(board)

          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.any?(&((pawns &&& Support.file_bb(Square.file(&1))) == 0))
        end)
      end),
      Feature.new("lines.rook_semi_open_file", 9, [{9, "rook op semi-open file"}], fn board ->
        per_color(board, fn board, color ->
          own = own_pawns(board, color)
          enemy = own_pawns(board, Board.opposite(color))

          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.any?(fn square ->
            file = Support.file_bb(Square.file(square))

            (own &&& file) == 0 and (enemy &&& file) != 0
          end)
        end)
      end),
      Feature.new("lines.open_file_control", 9, [{9, "controle over open file"}], fn board ->
        per_color(board, fn board, color ->
          own_pawns = own_pawns(board, color)
          occupancy = Board.occupancy(board)

          board
          |> heavy_squares(color)
          |> Enum.any?(fn square ->
            file = Square.file(square)

            (own_pawns &&& Support.file_bb(file)) == 0 and
              (AttackTables.rook_attacks(square, occupancy) &&& Support.file_bb(file))
              |> Support.popcount() >= 4
          end)
        end)
      end),
      Feature.new("lines.contested_files", 9, [{9, "contesting an open file"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)
          occupancy = Board.occupancy(board)
          enemy_counts = file_attack_counts(board, enemy, occupancy)
          own_counts = file_attack_counts(board, color, occupancy)

          Enum.any?(0..7, fn file ->
            Map.get(own_counts, file, 0) >= 3 and Map.get(enemy_counts, file, 0) >= 3
          end)
        end)
      end),
      Feature.new("lines.penetration", 9, [{9, "penetratie over open file"}], fn board ->
        per_color(board, fn board, color ->
          back_rank = back_rank_bb(color)
          occupancy = Board.occupancy(board)

          Board.piece_bb(board, color, :rooks)
          |> Bitboard.squares()
          |> Enum.any?(&((AttackTables.rook_attacks(&1, occupancy) &&& back_rank) != 0))
        end)
      end),
      Feature.new("lines.battery_on_file", 9, [{9, "batterij op file"}], fn board ->
        per_color(board, fn board, color ->
          pieces = pieces_of(board, color, @heavy)

          pieces
          |> each_pair()
          |> Enum.any?(fn {{_t1, a}, {_t2, b}} ->
            Square.file(a) == Square.file(b) and clear_between?(board, a, b)
          end)
        end)
      end),
      Feature.new("lines.battery_on_diagonal", 9, [{9, "batterij op diagonal"}], fn board ->
        per_color(board, fn board, color ->
          pieces = pieces_of(board, color, @diagonal_types)

          pieces
          |> each_pair()
          |> Enum.any?(fn {{_t1, a}, {_t2, b}} ->
            same_diagonal?(a, b) and clear_between?(board, a, b)
          end)
        end)
      end),
      Feature.new("lines.queen_rook_battery", 9, [{9, "queen-rook battery"}], fn board ->
        per_color(board, fn board, color ->
          queens = Bitboard.squares(Board.piece_bb(board, color, :queens))
          rooks = Bitboard.squares(Board.piece_bb(board, color, :rooks))

          for(queen <- queens, rook <- rooks, into: [], do: {queen, rook})
          |> Enum.any?(fn {a, b} ->
            (Square.file(a) == Square.file(b) or Square.rank(a) == Square.rank(b)) and
              clear_between?(board, a, b)
          end)
        end)
      end),
      Feature.new("lines.queen_bishop_battery", 9, [{9, "queen-bishop battery"}], fn board ->
        per_color(board, fn board, color ->
          queens = Bitboard.squares(Board.piece_bb(board, color, :queens))
          bishops = Bitboard.squares(Board.piece_bb(board, color, :bishops))

          for(queen <- queens, bishop <- bishops, into: [], do: {queen, bishop})
          |> Enum.any?(fn {a, b} ->
            same_diagonal?(a, b) and clear_between?(board, a, b)
          end)
        end)
      end),
      Feature.new("lines.bishop_battery", 9, [{9, "bishop battery"}], fn board ->
        per_color(board, fn board, color ->
          pieces = pieces_of(board, color, [:bishops])

          pieces
          |> each_pair()
          |> Enum.any?(fn {{_t1, a}, {_t2, b}} ->
            same_diagonal?(a, b) and clear_between?(board, a, b)
          end)
        end)
      end),
      Feature.new("lines.xray", 9, [{9, "x-ray langs file/rank/diagonal"}], fn board ->
        per_color(board, fn board, color ->
          pieces = pieces_of(board, color, [:rooks, :bishops, :queens])

          pieces
          |> each_pair()
          |> Enum.any?(fn {{t1, a}, {t2, b}} ->
            aligned_slider?(t1, t2, a, b) and own_piece_between?(board, color, a, b)
          end)
        end)
      end)
    ]
  end

  defp aligned_slider?(t1, t2, a, b) do
    heavy = t1 in @heavy and t2 in @heavy
    diagonal = t1 in @diagonal_types and t2 in @diagonal_types

    cond do
      heavy and (Square.file(a) == Square.file(b) or Square.rank(a) == Square.rank(b)) ->
        true

      diagonal and same_diagonal?(a, b) ->
        true

      true ->
        false
    end
  end

  defp own_piece_between?(board, color, a, b) do
    occupancy = Board.color_occupancy(board, color)

    squares_between(a, b)
    |> Enum.any?(&((occupancy &&& 1 <<< &1) != 0))
  end

  defp clear_between?(board, a, b) do
    squares_between(a, b)
    |> Enum.all?(&is_empty(board, &1))
  end

  defp squares_between(a, b) do
    step = step_size(a, b)

    (a + step)..b//step
    |> Enum.to_list()
    |> Enum.reject(&(&1 == b))
  end

  defp step_size(a, b) do
    df = sign(Square.file(b) - Square.file(a))
    dr = sign(Square.rank(b) - Square.rank(a))

    df + 8 * dr
  end

  defp sign(value) when value > 0, do: 1
  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 0

  defp same_diagonal?(a, b) do
    abs(Square.file(a) - Square.file(b)) == abs(Square.rank(a) - Square.rank(b))
  end

  defp file_attack_counts(board, color, occupancy) do
    board
    |> heavy_squares(color)
    |> Enum.reduce(%{}, fn square, counts ->
      attacks = AttackTables.rook_attacks(square, occupancy)

      0..7
      |> Enum.reduce(counts, fn file, counts ->
        if (attacks &&& Support.file_bb(file)) == 0 do
          counts
        else
          Map.update(counts, file, 1, &(&1 + 1))
        end
      end)
    end)
  end

  defp heavy_squares(board, color) do
    @heavy
    |> Enum.flat_map(&Bitboard.squares(Board.piece_bb(board, color, &1)))
    |> Enum.sort()
  end

  defp pieces_of(board, color, types) do
    types
    |> Enum.flat_map(fn type ->
      board |> Board.piece_bb(color, type) |> Bitboard.squares() |> Enum.map(&{type, &1})
    end)
    |> Enum.sort_by(fn {_type, square} -> square end)
  end

  defp each_pair(pieces) do
    for {first, index} <- Enum.with_index(pieces),
        {second, other_index} <- Enum.with_index(pieces),
        index < other_index,
        do: {first, second}
  end

  defp back_rank_bb(:white), do: 0xFF00000000000000
  defp back_rank_bb(:black), do: 0x00000000000000FF

  defp own_pawns(board, color), do: Board.piece_bb(board, color, :pawns)

  defp all_pawns(board) do
    Board.piece_bb(board, :white, :pawns) ||| Board.piece_bb(board, :black, :pawns)
  end

  defp own_pawn_files(board, color) do
    own_pawns(board, color)
    |> Bitboard.squares()
    |> Enum.map(&Square.file/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp pawn_files(board) do
    all_pawns(board)
    |> Bitboard.squares()
    |> Enum.map(&Square.file/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp diagonals do
    forward =
      for offset <- -7..7 do
        squares =
          for rank <- 0..7,
              file <- 0..7,
              file - rank == offset,
              do: rank * 8 + file

        {:forward, offset, squares}
      end

    backward =
      for offset <- 0..14 do
        squares =
          for rank <- 0..7,
              file <- 0..7,
              file + rank == offset,
              do: rank * 8 + file

        {:backward, offset, squares}
      end

    (forward ++ backward)
    |> Enum.filter(fn {_family, _key, squares} -> length(squares) >= 2 end)
  end

  defp label({_family, _key, squares}) do
    squares
    |> Enum.sort()
    |> Enum.map(&Square.to_string/1)
    |> then(fn [first, last | _rest] -> first <> last end)
  end

  defp is_empty(board, square) do
    (Board.occupancy(board) &&& 1 <<< square) == 0
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end
end
