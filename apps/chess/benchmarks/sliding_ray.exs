Mix.Task.run("app.start")

import Bitwise

alias Chess.Bitboard
alias Chess.Square

defmodule SlidingAttackBenchmark do
  @target Square.from_algebraic("e4")

  def run do
    boards = %{
      "rook open" => board_with(:rook, "h4"),
      "rook blocker near" => board_with(:rook, "h4", "g4"),
      "rook blocker far" => board_with(:rook, "h4", "f4"),
      "bishop open" => board_with(:bishop, "h7"),
      "bishop blocker near" => board_with(:bishop, "h7", "g6"),
      "bishop blocker far" => board_with(:bishop, "h7", "f5")
    }

    IO.puts("Correctness:")

    Enum.each(boards, fn {name, board} ->
      current = current_attack?(board, :white, @target)
      bitboard = bitboard_attack?(board, :white, @target)

      IO.puts(
        "  #{name}: current=#{current} bitboard=#{bitboard} " <>
          if(current == bitboard, do: "OK", else: "MISMATCH")
      )

      if current != bitboard do
        raise "benchmark variants disagree for #{name}"
      end
    end)

    IO.puts("")
    IO.puts("Benchmark:")

    Benchee.run(
      benchmark_cases(boards),
      warmup: 2,
      time: 5,
      memory_time: 2,
      parallel: 1,
      formatters: [
        Benchee.Formatters.Console
      ]
    )
  end

  defp benchmark_cases(boards) do
    Enum.reduce(boards, %{}, fn {name, board}, acc ->
      Map.merge(acc, %{
        "#{name}: current" => fn ->
          current_attack?(board, :white, @target)
        end,
        "#{name}: bitboard" => fn ->
          bitboard_attack?(board, :white, @target)
        end
      })
    end)
  end

  # This is the same algorithm used by the current attacked?/3 implementation.
  defp current_attack?(board, color, square) do
    occupied = Bitboard.occupied(board)

    rook_attack =
      ray_attacked?(
        board,
        occupied,
        square,
        [8, -8, 1, -1],
        color,
        [:rook, :queen]
      )

    bishop_attack =
      ray_attacked?(
        board,
        occupied,
        square,
        [9, 7, -7, -9],
        color,
        [:bishop, :queen]
      )

    rook_attack or bishop_attack
  end

  # Same attack semantics, but use the existing attack-generation functions.
  defp bitboard_attack?(board, :white, square) do
    rook_attackers =
      board.white_rooks |||
        board.white_queens

    bishop_attackers =
      board.white_bishops |||
        board.white_queens

    (Bitboard.rook_attacks(board, square) &&& rook_attackers) != 0 or
      (Bitboard.bishop_attacks(board, square) &&& bishop_attackers) != 0
  end

  defp ray_attacked?(board, occupied, square, steps, color, piece_types) do
    Enum.any?(steps, fn step ->
      first_piece_on_ray(board, occupied, square, step, color, piece_types)
    end)
  end

  defp first_piece_on_ray(board, occupied, square, step, color, piece_types) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      if (occupied &&& 1 <<< next) != 0 do
        mask = 1 <<< next

        case piece_types do
          [:rook, :queen] ->
            (board_piece(board, color, :rook) &&& mask) != 0 or
              (board_piece(board, color, :queen) &&& mask) != 0

          [:bishop, :queen] ->
            (board_piece(board, color, :bishop) &&& mask) != 0 or
              (board_piece(board, color, :queen) &&& mask) != 0
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

  defp board_piece(board, :white, :rook), do: board.white_rooks
  defp board_piece(board, :white, :bishop), do: board.white_bishops
  defp board_piece(board, :white, :queen), do: board.white_queens

  defp valid_ray_square?(_from, to, step) when step in [8, -8] do
    to in 0..63
  end

  defp valid_ray_square?(from, to, 1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -1) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, 9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, 7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp valid_ray_square?(from, to, -7) do
    to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  end

  defp valid_ray_square?(from, to, -9) do
    to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  end

  defp board_with(piece_type, source, blocker \\ nil) do
    board =
      Bitboard.empty()
      |> Bitboard.put(Square.from_algebraic(source), {:white, piece_type})

    if blocker do
      Bitboard.put(
        board,
        Square.from_algebraic(blocker),
        {:white, :pawn}
      )
    else
      board
    end
  end
end

SlidingAttackBenchmark.run()
