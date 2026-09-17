defmodule Chess.Bitboard.AttackTables do
  import Bitwise

  def king_attacks do
    List.to_tuple(for square <- 0..63, do: king_attacks_for(square))
  end

  def knight_attacks do
    List.to_tuple(for square <- 0..63, do: knight_attacks_for(square))
  end

  def pawn_attacks(direction) do
    List.to_tuple(for square <- 0..63, do: pawn_attacks_for(square, direction))
  end

  defp king_attacks_for(square) do
    file = rem(square, 8)
    rank = div(square, 8)

    for file_offset <- -1..1,
        rank_offset <- -1..1,
        file_offset != 0 or rank_offset != 0,
        target_file = file + file_offset,
        target_rank = rank + rank_offset,
        target_file in 0..7,
        target_rank in 0..7,
        reduce: 0 do
      attacks ->
        target = target_rank * 8 + target_file
        attacks ||| 1 <<< target
    end
  end

  defp knight_attacks_for(square) do
    file = rem(square, 8)
    rank = div(square, 8)

    Enum.reduce(
      [
        {-2, -1},
        {-2, 1},
        {-1, -2},
        {-1, 2},
        {1, -2},
        {1, 2},
        {2, -1},
        {2, 1}
      ],
      0,
      fn {file_offset, rank_offset}, attacks ->
        target_file = file + file_offset
        target_rank = rank + rank_offset

        if target_file in 0..7 and target_rank in 0..7 do
          target = target_rank * 8 + target_file
          attacks ||| 1 <<< target
        else
          attacks
        end
      end
    )
  end

  defp pawn_attacks_for(square, direction) do
    file = rem(square, 8)
    rank = div(square, 8)
    target_rank = rank + direction

    if target_rank in 0..7 do
      left = if file > 0, do: 1 <<< (target_rank * 8 + file - 1), else: 0
      right = if file < 7, do: 1 <<< (target_rank * 8 + file + 1), else: 0

      left ||| right
    else
      0
    end
  end
end
