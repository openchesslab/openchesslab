defmodule Analysis.OutpostBitboardComparison do
  @moduledoc false

  import Bitwise

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  @board_mask 0xFFFFFFFFFFFFFFFF
  @not_a_file 0xFEFEFEFEFEFEFEFE
  @not_h_file 0x7F7F7F7F7F7F7F7F

  @white_opponent_half 0xFFFFFFFF00000000
  @black_opponent_half 0x00000000FFFFFFFF

  def run do
    games = positive_env!("OUTPOST_BENCH_GAMES", 200)
    plies = positive_env!("OUTPOST_BENCH_PLIES", 12)
    runs = positive_env!("OUTPOST_BENCH_RUNS", 5)

    validate_pawn_attack_masks!()

    IO.puts("Generating position samples...")

    positions =
      build_positions(games, plies) ++ curated_positions()

    validate_equivalence!(positions)

    IO.puts("""

    Knight outpost A/B benchmark

    game lines:          #{games}
    maximum plies:       #{plies}
    positions:           #{length(positions)}
    runs:                #{runs}
    PostgreSQL:          not used

    Both implementations receive the same Chess.Position values.
    Timings include conversion from Position to Bitboard.
    """)

    current = &PositionProperties.outposts/1
    candidate = &bitboard_outposts/1

    # Warm both implementations before measuring.
    measure(positions, current)
    measure(positions, candidate)

    results =
      Enum.map(1..runs, fn run ->
        if rem(run, 2) == 1 do
          {current_us, current_checksum} =
            measure(positions, current)

          {candidate_us, candidate_checksum} =
            measure(positions, candidate)

          if current_checksum != candidate_checksum do
            raise "A/B checksum mismatch"
          end

          {current_us, candidate_us}
        else
          {candidate_us, candidate_checksum} =
            measure(positions, candidate)

          {current_us, current_checksum} =
            measure(positions, current)

          if current_checksum != candidate_checksum do
            raise "A/B checksum mismatch"
          end

          {current_us, candidate_us}
        end
      end)

    {current_times, candidate_times} =
      Enum.unzip(results)

    current_median = median(current_times)
    candidate_median = median(candidate_times)

    count = length(positions)

    IO.puts("""
    Results (median)

    Current implementation:
      total:       #{Float.round(current_median / 1000, 3)} ms
      per position: #{Float.round(current_median / count, 3)} us

    Bitboard candidate:
      total:       #{Float.round(candidate_median / 1000, 3)} ms
      per position: #{Float.round(candidate_median / count, 3)} us

    Current / candidate:
      #{Float.round(current_median / candidate_median, 2)}x

    The candidate was checked for exact result equality against
    the current implementation before timing.
    """)
  end

  defp bitboard_outposts(position) do
    board = Bitboard.from_position(position)

    white_control =
      pawn_attack_mask(board.white_pawns, :white)

    black_control =
      pawn_attack_mask(board.black_pawns, :black)

    white_outposts =
      board.white_knights
      |> band(@white_opponent_half)
      |> band(white_control)
      |> band(bnot(black_control))
      |> squares()

    black_outposts =
      board.black_knights
      |> band(@black_opponent_half)
      |> band(black_control)
      |> band(bnot(white_control))
      |> squares()

    %{
      white: white_outposts,
      black: black_outposts
    }
  end

  defp pawn_attack_mask(pawns, :white) do
    left = (pawns &&& @not_a_file) <<< 7
    right = (pawns &&& @not_h_file) <<< 9

    (left ||| right) &&& @board_mask
  end

  defp pawn_attack_mask(pawns, :black) do
    left = (pawns &&& @not_a_file) >>> 9
    right = (pawns &&& @not_h_file) >>> 7

    left ||| right
  end

  defp squares(mask) do
    for square <- 0..63,
        (mask &&& 1 <<< square) != 0,
        do: square
  end

  defp validate_pawn_attack_masks! do
    for color <- [:white, :black],
        square <- 0..63 do
      actual =
        pawn_attack_mask(1 <<< square, color)

      expected =
        Bitboard.pawn_attacks(color, square)

      if actual != expected do
        raise """
        Pawn attack mismatch:
        color=#{color}
        square=#{square}
        expected=#{expected}
        actual=#{actual}
        """
      end
    end
  end

  defp validate_equivalence!(positions) do
    positions
    |> Enum.with_index(1)
    |> Enum.each(fn {position, index} ->
      expected =
        PositionProperties.outposts(position)

      actual =
        bitboard_outposts(position)

      if expected != actual do
        raise """
        Outpost mismatch at sample #{index}

        expected: #{inspect(expected)}
        actual:   #{inspect(actual)}
        """
      end
    end)

    IO.puts("Correctness: #{length(positions)} positions matched exactly.")
  end

  defp curated_positions do
    white =
      Position.new()
      |> place("d4", {:white, :pawn})
      |> place("e5", {:white, :knight})

    black =
      Position.new()
      |> place("e5", {:black, :pawn})
      |> place("d4", {:black, :knight})

    [
      Position.new(),
      Position.starting_position(),
      white,
      place(white, "f6", {:black, :pawn}),
      black,
      place(black, "c3", {:white, :pawn}),
      Position.new()
      |> place("g4", {:white, :pawn})
      |> place("h5", {:white, :knight}),
      Position.new()
      |> place("b5", {:black, :pawn})
      |> place("a4", {:black, :knight})
    ]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(
      position,
      Square.from_algebraic(algebraic),
      piece
    )
  end

  defp build_positions(games, plies) do
    Enum.reduce(1..games, [], fn seed, accumulated ->
      {_last, accumulated} =
        Enum.reduce(
          1..plies,
          {Position.starting_position(), accumulated},
          fn ply, {position, rows} ->
            case Position.legal_moves(position) do
              [] ->
                {position, rows}

              moves ->
                index =
                  rem(seed * 19 + ply * 7, length(moves))

                move = Enum.at(moves, index)

                case Position.apply_move(position, move) do
                  {:ok, next_position} ->
                    {next_position, [next_position | rows]}

                  {:error, reason} ->
                    raise "Generated move failed: #{inspect(reason)}"
                end
            end
          end
        )

      accumulated
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp measure(positions, fun) do
    :erlang.garbage_collect()

    started = System.monotonic_time(:microsecond)

    checksum =
      Enum.reduce(positions, 0, fn position, total ->
        result = fun.(position)

        total +
          length(result.white) +
          length(result.black)
      end)

    elapsed =
      System.monotonic_time(:microsecond) - started

    {elapsed, checksum}
  end

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      (Enum.at(sorted, middle - 1) +
         Enum.at(sorted, middle)) / 2
    end
  end

  defp positive_env!(name, default) do
    raw =
      System.get_env(name, Integer.to_string(default))

    case Integer.parse(raw) do
      {number, ""} when number > 0 ->
        number

      _ ->
        raise "#{name} must be positive, got #{inspect(raw)}"
    end
  end
end

Analysis.OutpostBitboardComparison.run()
