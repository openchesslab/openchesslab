alias Chess.Bitboard
alias Chess.Board
alias Chess.Position

defmodule AttackedBreakdownBenchmark do
  import Bitwise

  def starting_position do
    Position.starting_position()
  end

  def middlegame_position do
    Position.new(
      board:
        Board.empty()
        |> Board.put(4, {:white, :king})     # e1
        |> Board.put(6, {:white, :knight})   # g1
        |> Board.put(11, {:white, :pawn})    # d2
        |> Board.put(12, {:white, :pawn})    # e2
        |> Board.put(21, {:white, :bishop})  # f3
        |> Board.put(28, {:white, :pawn})    # e4
        |> Board.put(35, {:white, :pawn})    # d5
        |> Board.put(36, {:black, :pawn})    # e5
        |> Board.put(43, {:black, :pawn})    # d6
        |> Board.put(51, {:black, :pawn})    # d7
        |> Board.put(60, {:black, :king})    # e8
        |> Board.put(62, {:black, :knight}), # g8
      side_to_move: :white
    )
  end

  def in_check_position do
    Position.new(
      board:
        Board.empty()
        |> Board.put(4, {:white, :king})    # e1
        |> Board.put(12, {:white, :pawn})   # e2
        |> Board.put(60, {:black, :king})   # e8
        |> Board.put(52, {:black, :rook}),  # e7
      side_to_move: :white
    )
  end

  def sample(position) do
    board = Bitboard.from_position(position)
    color = opposite_color(position.side_to_move)
    square = king_square(position, position.side_to_move)

    {board, color, square}
  end

  #
  # Individual components of Bitboard.attacked?/3
  #

  def occupied({board, _color, _square}) do
    Bitboard.occupied(board)
  end

  def pawn_check({board, color, square}) do
    attackers = Bitboard.pawn_attacks(opposite_color(color), square)
    pawns = color_pawns(board, color)

    (attackers &&& pawns) != 0
  end

  def knight_check({board, color, square}) do
    attackers = Bitboard.knight_attacks(square)
    knights = color_knights(board, color)

    (attackers &&& knights) != 0
  end

  def king_check({board, color, square}) do
    attackers = Bitboard.king_attacks(square)
    king = color_king(board, color)

    (attackers &&& king) != 0
  end

  #
  # Sliding attack components.
  #
  # These reproduce the current attacked?/3 ray traversal locally,
  # using only the existing public Bitboard API.
  #

  def rook_check({board, color, square}) do
    occupied = Bitboard.occupied(board)

    ray_attacked?(
      board,
      occupied,
      square,
      [8, -8, 1, -1],
      color,
      [:rook, :queen]
    )
  end

  def bishop_check({board, color, square}) do
    occupied = Bitboard.occupied(board)

    ray_attacked?(
      board,
      occupied,
      square,
      [9, 7, -7, -9],
      color,
      [:bishop, :queen]
    )
  end

  #
  # Full attack calculation, equivalent to the current implementation.
  #

  def all_components(sample) do
    {
      pawn_check(sample),
      knight_check(sample),
      king_check(sample),
      rook_check(sample),
      bishop_check(sample)
    }
  end

  def current_attacked?({board, color, square}) do
    Bitboard.attacked?(board, color, square)
  end

  #
  # Alternative evaluation order.
  #
  # This is NOT production code. It is only used to measure whether
  # short-circuiting can make a material difference.
  #

  def short_circuit_attacked?({board, color, square}) do
    pawn_attacked? =
      Bitboard.pawn_attacks(opposite_color(color), square)
      |> band(color_pawns(board, color))
      |> Kernel.!=(0)

    if pawn_attacked? do
      true
    else
      knight_attacked? =
        Bitboard.knight_attacks(square)
        |> band(color_knights(board, color))
        |> Kernel.!=(0)

      if knight_attacked? do
        true
      else
        king_attacked? =
          Bitboard.king_attacks(square)
          |> band(color_king(board, color))
          |> Kernel.!=(0)

        if king_attacked? do
          true
        else
          occupied = Bitboard.occupied(board)

          rook_attacked? =
            ray_attacked?(
              board,
              occupied,
              square,
              [8, -8, 1, -1],
              color,
              [:rook, :queen]
            )

          if rook_attacked? do
            true
          else
            ray_attacked?(
              board,
              occupied,
              square,
              [9, 7, -7, -9],
              color,
              [:bishop, :queen]
            )
          end
        end
      end
    end
  end

  #
  # Force each component independently, so we can see its individual cost.
  #

  def pawn_only(sample), do: pawn_check(sample)
  def knight_only(sample), do: knight_check(sample)
  def king_only(sample), do: king_check(sample)
  def rook_only(sample), do: rook_check(sample)
  def bishop_only(sample), do: bishop_check(sample)

  #
  # Helpers copied from the current Bitboard implementation.
  #

  defp color_pawns(board, :white), do: board.white_pawns
  defp color_pawns(board, :black), do: board.black_pawns

  defp color_knights(board, :white), do: board.white_knights
  defp color_knights(board, :black), do: board.black_knights

  defp color_king(board, :white), do: board.white_king
  defp color_king(board, :black), do: board.black_king

  defp color_rooks(board, :white), do: board.white_rooks
  defp color_rooks(board, :black), do: board.black_rooks

  defp color_bishops(board, :white), do: board.white_bishops
  defp color_bishops(board, :black), do: board.black_bishops

  defp color_queens(board, :white), do: board.white_queens
  defp color_queens(board, :black), do: board.black_queens

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

  defp king_square(position, color) do
    position.board
    |> Board.pieces()
    |> Enum.find_value(fn
      {square, {^color, :king}} -> square
      _ -> nil
    end)
  end

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white
end

positions = %{
  starting: AttackedBreakdownBenchmark.starting_position(),
  middlegame: AttackedBreakdownBenchmark.middlegame_position(),
  in_check: AttackedBreakdownBenchmark.in_check_position()
}

samples =
  Map.new(positions, fn {name, position} ->
    {name, AttackedBreakdownBenchmark.sample(position)}
  end)

IO.puts("Attack samples:\n")

Enum.each(samples, fn {name, {_board, color, square}} ->
  IO.puts("#{name}: color=#{color}, target=#{square}")
end)

IO.puts("\nResults:\n")

benchmarks =
  Enum.flat_map(samples, fn {name, sample} ->
    [
      {"#{name}: pawn", fn ->
        AttackedBreakdownBenchmark.pawn_only(sample)
      end},
      {"#{name}: knight", fn ->
        AttackedBreakdownBenchmark.knight_only(sample)
      end},
      {"#{name}: king", fn ->
        AttackedBreakdownBenchmark.king_only(sample)
      end},
      {"#{name}: rook", fn ->
        AttackedBreakdownBenchmark.rook_only(sample)
      end},
      {"#{name}: bishop", fn ->
        AttackedBreakdownBenchmark.bishop_only(sample)
      end},
      {"#{name}: all components", fn ->
        AttackedBreakdownBenchmark.all_components(sample)
      end},
      {"#{name}: attacked?", fn ->
        AttackedBreakdownBenchmark.current_attacked?(sample)
      end},
      {"#{name}: short circuit", fn ->
        AttackedBreakdownBenchmark.short_circuit_attacked?(sample)
      end}
    ]
  end)

Benchee.run(
  benchmarks,
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  formatters: [
    Benchee.Formatters.Console
  ]
)
