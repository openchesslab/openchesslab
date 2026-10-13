# Compare modulo-based ray boundary checks with equivalent 3-bit file checks.
# Does not modify production code or access PostgreSQL.
# Run from the OpenChessLab repository root:
#   mix run --no-start apps/analysis/benchmarks/ray_edge_comparison.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.RayEdgeComparison do
  @moduledoc false

  import Bitwise

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Bitboard

  @rook_steps [8, -8, 1, -1]
  @bishop_steps [9, 7, -7, -9]

  def current(occupied, square, steps, attackers) do
    Enum.any?(steps, fn step -> first_current(occupied, square, step, attackers) end)
  end

  def candidate(occupied, square, steps, attackers) do
    Enum.any?(steps, fn step -> first_candidate(occupied, square, step, attackers) end)
  end

  # Both variants use identical ray traversal; only the board-edge predicate differs.
  defp first_current(occupied, square, step, attackers) do
    next = square + step

    if current_valid?(square, next, step) do
      mask = 1 <<< next

      if (occupied &&& mask) == 0 do
        first_current(occupied, next, step, attackers)
      else
        (attackers &&& mask) != 0
      end
    else
      false
    end
  end

  defp first_candidate(occupied, square, step, attackers) do
    next = square + step

    if candidate_valid?(square, next, step) do
      mask = 1 <<< next

      if (occupied &&& mask) == 0 do
        first_candidate(occupied, next, step, attackers)
      else
        (attackers &&& mask) != 0
      end
    else
      false
    end
  end

  # Identical to the currently deployed Bitboard.valid_ray_square?/3.
  defp current_valid?(_from, to, step) when step in [8, -8], do: to in 0..63
  defp current_valid?(from, to, 1), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp current_valid?(from, to, -1), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  defp current_valid?(from, to, 9), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp current_valid?(from, to, 7), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1
  defp current_valid?(from, to, -7), do: to in 0..63 and rem(to, 8) == rem(from, 8) + 1
  defp current_valid?(from, to, -9), do: to in 0..63 and rem(to, 8) == rem(from, 8) - 1

  # The low three square bits encode the file (0=a, 7=h). A step that
  # increases file must not start on h; a decreasing step must not start on a.
  defp candidate_valid?(_from, to, step) when step in [8, -8], do: to in 0..63

  defp candidate_valid?(from, to, step) when step in [1, 9, -7],
    do: to in 0..63 and (from &&& 7) != 7

  defp candidate_valid?(from, to, step) when step in [-1, 7, -9],
    do: to in 0..63 and (from &&& 7) != 0

  def run do
    games = env_int("RAY_EDGE_GAMES", 20)
    plies = env_int("RAY_EDGE_PLIES", 80)
    runs = env_int("RAY_EDGE_RUNS", 7)
    repetitions = env_int("RAY_EDGE_REPETITIONS", 8)
    sample_count = env_int("RAY_EDGE_TIMED_BOARDS", 80)

    if games < 1 or plies < 2 or plies > 120 or runs < 3 or rem(runs, 2) == 0 or
         repetitions < 1 or sample_count < 1 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, odd runs >= 3, repetitions >= 1, sampled boards >= 1"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-ray-edge-#{System.unique_integer([:positive, :monotonic])}.pgn"
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
            raise "Unable to parse PGN fixture: #{inspect(other)}"
        end

      boards = Enum.map(positions, &Bitboard.from_position/1)

      extra_boards = [
        Bitboard.empty(),
        Bitboard.empty() |> Bitboard.put(0, {:white, :rook}),
        Bitboard.empty() |> Bitboard.put(63, {:black, :bishop}),
        Bitboard.empty() |> Bitboard.put(7, {:white, :queen}),
        Bitboard.empty() |> Bitboard.put(56, {:black, :queen}),
        Bitboard.empty()
        |> Bitboard.put(0, {:white, :queen})
        |> Bitboard.put(8, {:black, :pawn})
        |> Bitboard.put(9, {:black, :bishop})
      ]

      # Verify all colors, ray types, and target squares for every legal position.
      Enum.each(boards ++ extra_boards, fn board ->
        board |> cases_for_board() |> verify!()
      end)

      stride = max(div(length(boards), sample_count), 1)
      selected = boards |> Enum.take_every(stride) |> Enum.take(sample_count)
      cases = Enum.flat_map(selected, &cases_for_board/1)

      {_, expected} = measure(cases, repetitions, &current/4)
      {_, ^expected} = measure(cases, repetitions, &candidate/4)

      IO.puts("""
      Ray boundary comparison (no database)

      games:                  #{games}
      plies/game:             #{plies}
      legal positions:        #{length(positions)}
      timed boards:           #{length(selected)}
      distinct ray checks:    #{length(cases)}
      checks per run:         #{length(cases) * repetitions}
      runs:                   #{runs}
      """)

      samples =
        Enum.map(1..runs, fn run ->
          {current_us, candidate_us} =
            if rem(run, 2) == 1 do
              {a_us, ^expected} = measure(cases, repetitions, &current/4)
              {b_us, ^expected} = measure(cases, repetitions, &candidate/4)
              {a_us, b_us}
            else
              {b_us, ^expected} = measure(cases, repetitions, &candidate/4)
              {a_us, ^expected} = measure(cases, repetitions, &current/4)
              {a_us, b_us}
            end

          IO.puts("  current: #{ms(current_us)} ms | bitmask: #{ms(candidate_us)} ms")
          {current_us, candidate_us}
        end)

      a = samples |> Enum.map(&elem(&1, 0)) |> median()
      b = samples |> Enum.map(&elem(&1, 1)) |> median()

      IO.puts("""
      Current median: #{ms(a)} ms
      Bitmask median: #{ms(b)} ms
      Bitmask/current: #{Float.round(b / a, 3)}x
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
      a = current(occupied, square, steps, attackers)
      b = candidate(occupied, square, steps, attackers)

      if a != b do
        raise "Ray boundary mismatch for square #{square}, steps #{inspect(steps)}: #{inspect(a)} vs #{inspect(b)}"
      end
    end)
  end

  defp measure(cases, repetitions, fun) do
    :erlang.garbage_collect()

    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, count ->
        Enum.reduce(cases, count, fn {occupied, square, steps, attackers}, acc ->
          if fun.(occupied, square, steps, attackers), do: acc + 1, else: acc
        end)
      end)
    end)
  end

  defp env_int(name, default) do
    name |> System.get_env(Integer.to_string(default)) |> String.to_integer()
  end

  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))
  defp ms(us), do: :erlang.float_to_binary(us / 1_000, decimals: 2)
end

Analysis.RayEdgeComparison.run()
