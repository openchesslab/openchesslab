# Compare the existing Enum.any?/2 ray dispatch with four direct, short-circuit
# ray checks. Both variants use the exact same step-by-step ray implementation.
# Run from the OpenChessLab umbrella root:
#   mix run --no-start apps/analysis/benchmarks/ray_dispatch_comparison.exs
# No database is started or accessed.

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.RayDispatchComparison do
  @moduledoc false

  import Bitwise

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Bitboard

  @rook_steps [8, -8, 1, -1]
  @bishop_steps [9, 7, -7, -9]

  # Exact existing dispatch in Bitboard.ray_attacked?/4.
  def current_ray_attacked?(occupied, square, steps, attackers) do
    Enum.any?(steps, fn step ->
      first_piece_on_ray(occupied, square, step, attackers)
    end)
  end

  # Candidate: eliminate the temporary direction list traversal and callback.
  # The two production callers always pass exactly four directions.
  def direct_ray_attacked?(occupied, square, [a, b, c, d], attackers) do
    first_piece_on_ray(occupied, square, a, attackers) or
      first_piece_on_ray(occupied, square, b, attackers) or
      first_piece_on_ray(occupied, square, c, attackers) or
      first_piece_on_ray(occupied, square, d, attackers)
  end

  # Keep this implementation identical for both benchmark variants, so the
  # measurement isolates ray dispatch rather than ray traversal or masks.
  defp first_piece_on_ray(occupied, square, step, attackers) do
    next = square + step

    if valid_ray_square?(square, next, step) do
      mask = 1 <<< next

      if (occupied &&& mask) == 0 do
        first_piece_on_ray(occupied, next, step, attackers)
      else
        (attackers &&& mask) != 0
      end
    else
      false
    end
  end

  defp valid_ray_square?(_from, to, step) when step in [8, -8], do: to in 0..63
  defp valid_ray_square?(from, to, 1), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp valid_ray_square?(from, to, -1), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  defp valid_ray_square?(from, to, 9), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp valid_ray_square?(from, to, 7), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  defp valid_ray_square?(from, to, -7), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp valid_ray_square?(from, to, -9), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1

  def run do
    games = env_integer("RAY_DISPATCH_GAMES", 20)
    plies = env_integer("RAY_DISPATCH_PLIES", 80)
    runs = env_integer("RAY_DISPATCH_RUNS", 7)
    repetitions = env_integer("RAY_DISPATCH_REPETITIONS", 8)
    timed_boards = env_integer("RAY_DISPATCH_TIMED_BOARDS", 80)

    if games < 1 or plies < 2 or plies > 120 or runs < 1 or rem(runs, 2) == 0 or
         repetitions < 1 or timed_boards < 1 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, odd runs >= 1, repetitions >= 1, timed boards >= 1"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-ray-dispatch-#{System.unique_integer([:positive, :monotonic])}.pgn"
      )

    try do
      PgnLongGameFixture.build_fixture(path, games, plies, 0)
      pgn = File.read!(path)

      positions =
        case PgnBatchImporter.parse(pgn) do
          {:ok, parsed} when length(parsed) == games ->
            Enum.flat_map(parsed, fn %{initial_position: initial, replay: replay} ->
              [initial | Enum.map(replay, fn {_move, position} -> position end)]
            end)

          other ->
            raise "Could not parse PGN fixture: #{inspect(other)}"
        end

      boards = Enum.map(positions, &Bitboard.from_position/1)
      stride = max(div(length(boards), timed_boards), 1)
      selected_boards = boards |> Enum.take_every(stride) |> Enum.take(timed_boards)
      cases = Enum.flat_map(selected_boards, &cases_for_board/1)

      # Empty, edge, and blocker cases supplement the legal game positions.
      extra_boards = [
        Bitboard.empty(),
        Bitboard.empty() |> Bitboard.put(0, {:white, :rook}),
        Bitboard.empty() |> Bitboard.put(63, {:black, :bishop}),
        Bitboard.empty()
        |> Bitboard.put(0, {:white, :queen})
        |> Bitboard.put(8, {:black, :pawn})
        |> Bitboard.put(9, {:black, :bishop})
      ]

      extra_cases = Enum.flat_map(extra_boards, &cases_for_board/1)
      verify!(cases ++ extra_cases)

      {_, expected} = measure(cases, repetitions, &current_ray_attacked?/4)
      {_, ^expected} = measure(cases, repetitions, &direct_ray_attacked?/4)

      IO.puts("""
      Ray dispatch comparison (no database)

      games:                  #{games}
      plies/game:             #{plies}
      legal positions:        #{length(positions)}
      timed boards:           #{length(selected_boards)}
      distinct ray checks:    #{length(cases)}
      checks per run:         #{length(cases) * repetitions}
      runs:                   #{runs}
      """)

      measurements =
        Enum.map(1..runs, fn run ->
          {current_us, direct_us} =
            if rem(run, 2) == 1 do
              {a_us, ^expected} = measure(cases, repetitions, &current_ray_attacked?/4)
              {b_us, ^expected} = measure(cases, repetitions, &direct_ray_attacked?/4)
              {a_us, b_us}
            else
              {b_us, ^expected} = measure(cases, repetitions, &direct_ray_attacked?/4)
              {a_us, ^expected} = measure(cases, repetitions, &current_ray_attacked?/4)
              {a_us, b_us}
            end

          IO.puts("  current: #{format_ms(current_us)} ms | direct: #{format_ms(direct_us)} ms")
          {current_us, direct_us}
        end)

      current_median = measurements |> Enum.map(&elem(&1, 0)) |> median()
      direct_median = measurements |> Enum.map(&elem(&1, 1)) |> median()

      IO.puts("""
      Current median: #{format_ms(current_median)} ms
      Direct median:  #{format_ms(direct_median)} ms
      Direct/current: #{Float.round(direct_median / current_median, 3)}x
      """)
    after
      File.rm(path)
    end
  end

  defp cases_for_board(board) do
    occupied = Bitboard.occupied(board)

    for square <- 0..63,
        color <- [:white, :black],
        steps <- [@rook_steps, @bishop_steps] do
      attackers =
        case {color, steps} do
          {:white, @rook_steps} -> board.white_rooks ||| board.white_queens
          {:black, @rook_steps} -> board.black_rooks ||| board.black_queens
          {:white, @bishop_steps} -> board.white_bishops ||| board.white_queens
          {:black, @bishop_steps} -> board.black_bishops ||| board.black_queens
        end

      {occupied, square, steps, attackers}
    end
  end

  defp verify!(cases) do
    Enum.each(cases, fn {occupied, square, steps, attackers} ->
      expected = current_ray_attacked?(occupied, square, steps, attackers)
      actual = direct_ray_attacked?(occupied, square, steps, attackers)

      if expected != actual do
        raise "Ray mismatch at #{square} / #{inspect(steps)}: #{inspect(expected)} vs #{inspect(actual)}"
      end
    end)
  end

  defp measure(cases, repetitions, ray_fun) do
    :erlang.garbage_collect()

    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, count ->
        Enum.reduce(cases, count, fn {occupied, square, steps, attackers}, acc ->
          if ray_fun.(occupied, square, steps, attackers), do: acc + 1, else: acc
        end)
      end)
    end)
  end

  defp env_integer(key, default) do
    key |> System.get_env(Integer.to_string(default)) |> String.to_integer()
  end

  defp median(values) do
    values |> Enum.sort() |> Enum.at(div(length(values), 2))
  end

  defp format_ms(microseconds) do
    :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
  end
end

Analysis.RayDispatchComparison.run()
