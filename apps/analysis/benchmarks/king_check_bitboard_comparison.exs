# Run from the OpenChessLab umbrella root:
#   mix run --no-start apps/analysis/benchmarks/king_check_bitboard_comparison.exs
#
# CHECK_BENCH_GAMES (default 200)
# CHECK_BENCH_PLIES (default 12)
# CHECK_BENCH_RUNS  (default 5)
#
# CPU-only: no PostgreSQL access, table changes, or PGN parsing.

defmodule Analysis.KingCheckBitboardComparison do
  @moduledoc false

  import Bitwise

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  def run do
    games = positive_env!("CHECK_BENCH_GAMES", 200)
    plies = positive_env!("CHECK_BENCH_PLIES", 12)
    runs = positive_env!("CHECK_BENCH_RUNS", 5)

    IO.puts("Generating legal-game samples (excluded from timings)...")

    positions = build_positions(games, plies) ++ curated_positions()

    validate_equivalence!(positions)

    IO.puts("""

    King check status A/B benchmark

    game lines:          #{games}
    maximum plies:       #{plies}
    sampled positions:   #{length(positions)}
    measured runs:       #{runs}
    PostgreSQL:          not used

    Both candidates receive Chess.Position values. Conversion to a
    Bitboard, king lookup, and check testing are included in timings.
    """)

    current = &PositionProperties.in_check/1
    candidate = &bitboard_in_check/1

    measure(positions, current)
    measure(positions, candidate)

    results =
      Enum.map(1..runs, fn run ->
        if rem(run, 2) == 1 do
          {current_us, current_checksum} = measure(positions, current)
          {candidate_us, candidate_checksum} = measure(positions, candidate)
          assert_same_checksum!(current_checksum, candidate_checksum)
          {current_us, candidate_us}
        else
          {candidate_us, candidate_checksum} = measure(positions, candidate)
          {current_us, current_checksum} = measure(positions, current)
          assert_same_checksum!(current_checksum, candidate_checksum)
          {current_us, candidate_us}
        end
      end)

    {current_times, candidate_times} = Enum.unzip(results)
    current_us = median(current_times)
    candidate_us = median(candidate_times)
    count = length(positions)

    IO.puts("""
    Results (median)

    Current PositionProperties.in_check/1:
      total:        #{Float.round(current_us / 1000, 3)} ms
      per position: #{Float.round(current_us / count, 3)} us

    One-bitboard candidate:
      total:        #{Float.round(candidate_us / 1000, 3)} ms
      per position: #{Float.round(candidate_us / count, 3)} us

    Current / candidate: #{Float.round(current_us / candidate_us, 2)}x

    Exact result equality was checked before timing, including kingless
    positions and hypothetical positions with multiple kings.
    """)
  end

  defp bitboard_in_check(position) do
    board = Bitboard.from_position(position)

    %{
      white: king_attacked?(board.white_king, board, :black),
      black: king_attacked?(board.black_king, board, :white)
    }
  end

  defp king_attacked?(0, _board, _attacking_color), do: false

  defp king_attacked?(kings, board, attacking_color) do
    # Board.pieces/1 enumerates squares in ascending order. For edited
    # positions with multiple kings, preserve Position.in_check?/2's
    # existing first-king semantics by selecting the lowest set bit.
    Bitboard.attacked?(board, attacking_color, first_square(kings, 0))
  end

  defp first_square(mask, square) do
    if (mask &&& 1) == 1 do
      square
    else
      first_square(mask >>> 1, square + 1)
    end
  end

  defp validate_equivalence!(positions) do
    Enum.each(Enum.with_index(positions, 1), fn {position, index} ->
      expected = PositionProperties.in_check(position)
      actual = bitboard_in_check(position)

      if expected != actual do
        raise """
        King check mismatch at sample #{index}:
        expected: #{inspect(expected)}
        actual:   #{inspect(actual)}
        """
      end
    end)

    IO.puts("Correctness: #{length(positions)} positions matched exactly.")
  end

  defp curated_positions do
    white_checked =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook})

    black_checked =
      Position.new()
      |> place("a1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})

    both_checked =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e4", {:black, :rook})
      |> place("e5", {:white, :rook})

    # The higher-index white king is attacked; the first one isn't.
    # Canonical Position.in_check?/2 evaluates only the first king.
    two_white_kings =
      Position.new()
      |> place("e1", {:white, :king})
      |> place("h7", {:white, :king})
      |> place("f8", {:black, :knight})

    two_black_kings =
      Position.new()
      |> place("a8", {:black, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})

    [
      Position.new(),
      Position.starting_position(),
      white_checked,
      black_checked,
      both_checked,
      two_white_kings,
      two_black_kings,
      place(Position.new(), "d1", {:white, :king}),
      place(Position.new(), "e8", {:black, :king})
    ]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, Square.from_algebraic(algebraic), piece)
  end

  defp build_positions(games, plies) do
    Enum.reduce(1..games, [], fn seed, acc ->
      {_last, acc} =
        Enum.reduce(1..plies, {Position.starting_position(), acc}, fn ply, {position, rows} ->
          case Position.legal_moves(position) do
            [] ->
              {position, rows}

            moves ->
              move = Enum.at(moves, rem(seed * 19 + ply * 7, length(moves)))

              case Position.apply_move(position, move) do
                {:ok, next_position} ->
                  {next_position, [next_position | rows]}

                {:error, reason} ->
                  raise "Generated legal move failed: #{inspect(reason)}"
              end
          end
        end)

      acc
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp measure(positions, fun) do
    :erlang.garbage_collect()
    start = System.monotonic_time(:microsecond)

    checksum =
      Enum.reduce(positions, 0, fn position, count ->
        %{white: white, black: black} = fun.(position)
        count + bool_count(white) + bool_count(black)
      end)

    {System.monotonic_time(:microsecond) - start, checksum}
  end

  defp assert_same_checksum!(same, same), do: :ok

  defp assert_same_checksum!(left, right) do
    raise "Checksums differ: current=#{left} candidate=#{right}"
  end

  defp bool_count(true), do: 1
  defp bool_count(false), do: 0

  defp median(values) do
    sorted = Enum.sort(values)
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1 do
      Enum.at(sorted, middle)
    else
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end

  defp positive_env!(name, default) do
    raw = System.get_env(name, Integer.to_string(default))

    case Integer.parse(raw) do
      {number, ""} when number > 0 -> number
      _ -> raise "#{name} must be a positive integer; got #{inspect(raw)}"
    end
  end
end

Analysis.KingCheckBitboardComparison.run()
