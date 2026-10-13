# Compare the existing king-square lookup with a direct tuple scan.
# Does not modify production code or access PostgreSQL.
# From the repository root:
#   mix run --no-start apps/analysis/benchmarks/king_square_comparison.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.KingSquareComparison do
  @moduledoc false

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Board
  alias Chess.Position

  # This reproduces the current lookup in Position.king_square/2 and in_check?/2.
  def current(%Position{board: board}, color) when color in [:white, :black] do
    board
    |> Board.pieces()
    |> Enum.find_value(fn
      {square, {^color, :king}} -> square
      _ -> nil
    end)
  end

  # The first matching square wins, as in Board.pieces/1's ascending order.
  def candidate(%Position{board: board}, color) when color in [:white, :black] do
    scan(board, color, 0)
  end

  defp scan(_board, _color, 64), do: nil

  defp scan(board, color, square) do
    case elem(board, square) do
      {^color, :king} -> square
      _ -> scan(board, color, square + 1)
    end
  end

  def run do
    games = env_integer("KING_SQUARE_BENCH_GAMES", 20)
    plies = env_integer("KING_SQUARE_BENCH_PLIES", 80)
    repetitions = env_integer("KING_SQUARE_BENCH_REPETITIONS", 16)
    runs = env_integer("KING_SQUARE_BENCH_RUNS", 7)

    if games < 1 or plies < 2 or plies > 120 or repetitions < 1 or runs < 1 or
         rem(runs, 2) == 0 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, repetitions >= 1, odd runs >= 1"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-king-lookup-#{System.unique_integer([:positive, :monotonic])}.pgn"
      )

    try do
      PgnLongGameFixture.build_fixture(path, games, plies, 0)

      positions =
        case PgnBatchImporter.parse(File.read!(path)) do
          {:ok, parsed} when length(parsed) == games ->
            Enum.flat_map(parsed, fn %{initial_position: initial, replay: replay} ->
              [initial | Enum.map(replay, fn {_move, position} -> position end)]
            end)

          other ->
            raise "Could not parse fixture: #{inspect(other)}"
        end

      verify!(positions)
      verify_edge_cases!()

      {_, checksum} = measure(positions, repetitions, &current/2)
      {_, ^checksum} = measure(positions, repetitions, &candidate/2)

      IO.puts("""
      King-square lookup comparison (no database)
      games:                  #{games}
      plies/game:             #{plies}
      legal positions:        #{length(positions)}
      lookups per run:        #{length(positions) * 2 * repetitions}
      runs:                   #{runs}
      """)

      measurements =
        for run <- 1..runs do
          {current_us, candidate_us} =
            if rem(run, 2) == 1 do
              {a_us, ^checksum} = measure(positions, repetitions, &current/2)
              {b_us, ^checksum} = measure(positions, repetitions, &candidate/2)
              {a_us, b_us}
            else
              {b_us, ^checksum} = measure(positions, repetitions, &candidate/2)
              {a_us, ^checksum} = measure(positions, repetitions, &current/2)
              {a_us, b_us}
            end

          IO.puts("  current: #{ms(current_us)} ms | direct scan: #{ms(candidate_us)} ms")
          {current_us, candidate_us}
        end

      a = measurements |> Enum.map(&elem(&1, 0)) |> median()
      b = measurements |> Enum.map(&elem(&1, 1)) |> median()

      IO.puts("""
      Current median:    #{ms(a)} ms
      Direct-scan median: #{ms(b)} ms
      Direct/current:    #{Float.round(b / a, 3)}x
      """)
    after
      File.rm(path)
    end
  end

  defp verify!(positions) do
    for position <- positions, color <- [:white, :black] do
      expected = current(position, color)
      actual = candidate(position, color)

      if expected != actual do
        raise "King-square mismatch for #{color}: #{inspect(expected)} vs #{inspect(actual)}"
      end
    end
  end

  defp verify_edge_cases! do
    empty = Position.new()
    verify!([empty])

    for square <- 0..63, color <- [:white, :black] do
      position = Position.put_piece(empty, square, {color, :king})
      verify!([position])
    end

    # Non-canonical analysis positions can have multiple kings. The old lookup
    # returns the smallest matching square, even in those positions.
    for color <- [:white, :black] do
      position =
        empty
        |> Position.put_piece(0, {color, :king})
        |> Position.put_piece(63, {color, :king})

      verify!([position])

      if candidate(position, color) != 0 do
        raise "Direct scan failed to preserve first-matching-king behavior"
      end
    end
  end

  defp measure(positions, repetitions, lookup) do
    :erlang.garbage_collect()

    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, total ->
        Enum.reduce(positions, total, fn position, acc ->
          acc + encode(lookup.(position, :white)) + encode(lookup.(position, :black))
        end)
      end)
    end)
  end

  defp encode(nil), do: 64
  defp encode(square), do: square

  defp env_integer(key, default) do
    key |> System.get_env(Integer.to_string(default)) |> String.to_integer()
  end

  defp median(values) do
    values |> Enum.sort() |> Enum.at(div(length(values), 2))
  end

  defp ms(microseconds) do
    :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
  end
end

Analysis.KingSquareComparison.run()
