defmodule AttackedCompositionBenchmark do
  import Bitwise

  alias Chess.Bitboard

  def run do
    starting = Bitboard.from_position(Chess.Position.starting_position())
    middlegame = middlegame_board()

    starting_square = 36
    middlegame_square = 28

    Benchee.run(
      [
        {
          "starting: occupied",
          fn ->
            Bitboard.occupied(starting)
          end
        },
        {
          "middlegame: occupied",
          fn ->
            Bitboard.occupied(middlegame)
          end
        },
        {
          "starting: pawn",
          fn ->
            pawn_attack?(starting, starting_square, :white)
          end
        },
        {
          "starting: pawn + knight",
          fn ->
            pawn_attack?(starting, starting_square, :white) or
              knight_attack?(starting, starting_square, :white)
          end
        },
        {
          "starting: pawn + knight + king",
          fn ->
            pawn_attack?(starting, starting_square, :white) or
              knight_attack?(starting, starting_square, :white) or
              king_attack?(starting, starting_square, :white)
          end
        },
        {
          "starting: pawn + knight + king + rook",
          fn ->
            occupied = Bitboard.occupied(starting)

            pawn_attack?(starting, starting_square, :white) or
              knight_attack?(starting, starting_square, :white) or
              king_attack?(starting, starting_square, :white) or
              ray_attacked?(
                starting,
                occupied,
                starting_square,
                [8, -8, 1, -1],
                :white,
                [:rook, :queen]
              )
          end
        },
        {
          "starting: all components",
          fn ->
            attacked_components(
              starting,
              starting_square,
              :white
            )
          end
        },
        {
          "starting: attacked?",
          fn ->
            Bitboard.attacked?(starting, :white, starting_square)
          end
        },
        {
          "middlegame: pawn + knight + king",
          fn ->
            pawn_attack?(middlegame, middlegame_square, :white) or
              knight_attack?(middlegame, middlegame_square, :white) or
              king_attack?(middlegame, middlegame_square, :white)
          end
        },
        {
          "middlegame: pawn + knight + king + rook",
          fn ->
            occupied = Bitboard.occupied(middlegame)

            pawn_attack?(middlegame, middlegame_square, :white) or
              knight_attack?(middlegame, middlegame_square, :white) or
              king_attack?(middlegame, middlegame_square, :white) or
              ray_attacked?(
                middlegame,
                occupied,
                middlegame_square,
                [8, -8, 1, -1],
                :white,
                [:rook, :queen]
              )
          end
        },
        {
          "middlegame: all components",
          fn ->
            attacked_components(
              middlegame,
              middlegame_square,
              :white
            )
          end
        },
        {
          "middlegame: attacked?",
          fn ->
            Bitboard.attacked?(
              middlegame,
              :white,
              middlegame_square
            )
          end
        }
      ],
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 1
    )
  end

  defp middlegame_board do
    Bitboard.empty()
    |> Bitboard.put(0, {:white, :king})
    |> Bitboard.put(4, {:black, :king})
    |> Bitboard.put(12, {:white, :pawn})
    |> Bitboard.put(21, {:white, :knight})
    |> Bitboard.put(27, {:black, :bishop})
    |> Bitboard.put(36, {:white, :rook})
    |> Bitboard.put(43, {:black, :queen})
    |> Bitboard.put(52, {:black, :pawn})
  end

  defp attacked_components(board, square, color) do
    occupied = Bitboard.occupied(board)

    pawn_hit = pawn_attack?(board, square, color)
    knight_hit = knight_attack?(board, square, color)
    king_hit = king_attack?(board, square, color)

    rook_hit =
      ray_attacked?(
        board,
        occupied,
        square,
        [8, -8, 1, -1],
        color,
        [:rook, :queen]
      )

    bishop_hit =
      ray_attacked?(
        board,
        occupied,
        square,
        [9, 7, -7, -9],
        color,
        [:bishop, :queen]
      )

    pawn_hit or
      knight_hit or
      king_hit or
      rook_hit or
      bishop_hit
  end

  defp pawn_attack?(board, square, color) do
    attackers =
      Bitboard.pawn_attacks(
        opposite_color(color),
        square
      )

    (attackers &&& color_pawns(board, color)) != 0
  end

  defp knight_attack?(board, square, color) do
    attackers = Bitboard.knight_attacks(square)

    (attackers &&& color_knights(board, color)) != 0
  end

  defp king_attack?(board, square, color) do
    attackers = Bitboard.king_attacks(square)

    (attackers &&& color_king(board, color)) != 0
  end

  defp ray_attacked?(board, occupied, square, steps, color, piece_types) do
    Enum.any?(steps, fn step ->
      first_piece_on_ray(
        board,
        occupied,
        square,
        step,
        color,
        piece_types
      )
    end)
  end

  defp first_piece_on_ray(
         board,
         occupied,
         square,
         step,
         color,
         piece_types
       ) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_types do
          [:rook, :queen] ->
            (color_rooks(board, color) &&& mask) != 0 or
              (color_queens(board, color) &&& mask) != 0

          [:bishop, :queen] ->
            (color_bishops(board, color) &&& mask) != 0 or
              (color_queens(board, color) &&& mask) != 0
        end
      else
        first_piece_on_ray(
          board,
          occupied,
          next,
          step,
          color,
          piece_types
        )
      end
    else
      false
    end
  end

  defp valid_ray_square?(_from, to, step)
       when step in [8, -8] do
    to in 0..63
  end

  defp valid_ray_square?(from, to, 1) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -1) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, 9) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and
      rem(to, 8) == rem(from, 8) - 1
  end

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white

  defp color_pawns(board, :white), do: board.white_pawns
  defp color_pawns(board, :black), do: board.black_pawns

  defp color_knights(board, :white), do: board.white_knights
  defp color_knights(board, :black), do: board.black_knights

  defp color_king(board, :white), do: board.white_king
  defp color_king(board, :black), do: board.black_king

  defp color_rooks(board, :white), do: board.white_rooks
  defp color_rooks(board, :black), do: board.black_rooks

  defp color_queens(board, :white), do: board.white_queens
  defp color_queens(board, :black), do: board.black_queens

  defp color_bishops(board, :white), do: board.white_bishops
  defp color_bishops(board, :black), do: board.black_bishops
end

AttackedCompositionBenchmark.run()
