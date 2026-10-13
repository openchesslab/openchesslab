# Compare the existing SAN check/checkmate suffix decision with checking once.
# This isolates the suffix decision; it does not include move application or
# the rest of SAN.parse/2 / SAN.format/2.
# Run from the OpenChessLab umbrella root:
#   mix run --no-start apps/analysis/benchmarks/san_check_suffix_comparison.exs
# No database is started or accessed.

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.SanCheckSuffixComparison do
  @moduledoc false

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Move
  alias Chess.Position

  # Mirrors Chess.Notation.SAN.check_suffix/2 after apply_move/2 succeeds.
  def current_suffix(next_position) do
    opponent = next_position.side_to_move

    cond do
      Position.checkmate?(next_position, opponent) -> "#"
      Position.in_check?(next_position, opponent) -> "+"
      true -> ""
    end
  end

  # Do one check test; generate legal moves only when the king is in check.
  def candidate_suffix(next_position) do
    opponent = next_position.side_to_move

    if Position.in_check?(next_position, opponent) do
      if Position.legal_moves(next_position) == [], do: "#", else: "+"
    else
      ""
    end
  end

  def run do
    games = env_integer("SAN_SUFFIX_GAMES", 20)
    plies = env_integer("SAN_SUFFIX_PLIES", 80)
    repetitions = env_integer("SAN_SUFFIX_REPETITIONS", 8)
    runs = env_integer("SAN_SUFFIX_RUNS", 7)

    if games < 1 or plies < 2 or plies > 120 or repetitions < 1 or runs < 3 or
         rem(runs, 2) == 0 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, repetitions >= 1 and odd runs >= 3"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-san-suffix-#{System.unique_integer([:positive, :monotonic])}.pgn"
      )

    try do
      PgnLongGameFixture.build_fixture(path, games, plies, 0)
      {:ok, parsed} = PgnBatchImporter.parse(File.read!(path))

      if length(parsed) != games do
        raise "Expected #{games} parsed games, got #{length(parsed)}"
      end

      positions =
        Enum.flat_map(parsed, fn %{replay: replay} ->
          Enum.map(replay, fn {_move, next_position} -> next_position end)
        end)

      if length(positions) != games * plies do
        raise "Incorrect number of replayed moves"
      end

      verify!(positions)
      verify_edge_cases!()

      frequencies = Enum.frequencies_by(positions, &current_suffix/1)

      {_, expected} = measure(positions, repetitions, &current_suffix/1)
      {_, ^expected} = measure(positions, repetitions, &candidate_suffix/1)

      IO.puts("""
      SAN check-suffix comparison (no database)

      games:                 #{games}
      plies/game:            #{plies}
      replay positions:      #{length(positions)}
      suffix checks per run: #{length(positions) * repetitions}
      no check:              #{Map.get(frequencies, "", 0)}
      check:                 #{Map.get(frequencies, "+", 0)}
      checkmate:             #{Map.get(frequencies, "#", 0)}
      runs:                  #{runs}
      """)

      timings =
        for run <- 1..runs do
          {current_us, candidate_us} =
            if rem(run, 2) == 1 do
              {a_us, ^expected} = measure(positions, repetitions, &current_suffix/1)
              {b_us, ^expected} = measure(positions, repetitions, &candidate_suffix/1)
              {a_us, b_us}
            else
              {b_us, ^expected} = measure(positions, repetitions, &candidate_suffix/1)
              {a_us, ^expected} = measure(positions, repetitions, &current_suffix/1)
              {a_us, b_us}
            end

          IO.puts("  current: #{ms(current_us)} ms | candidate: #{ms(candidate_us)} ms")
          {current_us, candidate_us}
        end

      current_median = timings |> Enum.map(&elem(&1, 0)) |> median()
      candidate_median = timings |> Enum.map(&elem(&1, 1)) |> median()

      IO.puts("""
      Current median:      #{ms(current_median)} ms
      Candidate median:    #{ms(candidate_median)} ms
      Candidate/current:   #{Float.round(candidate_median / current_median, 3)}x
      """)
    after
      File.rm(path)
    end
  end

  defp verify!(positions) do
    Enum.each(positions, fn position ->
      expected = current_suffix(position)
      actual = candidate_suffix(position)

      if expected != actual do
        raise "Suffix mismatch: #{inspect(expected)} vs #{inspect(actual)} at #{inspect(position)}"
      end
    end)
  end

  defp verify_edge_cases! do
    # A position without kings is intentionally allowed in analysis.
    verify!([Position.new(), Position.starting_position()])

    # Fool's Mate: 1. f3 e5 2. g4 Qh4#.
    mate =
      Enum.reduce([{13, 21}, {52, 36}, {14, 30}, {59, 31}], Position.starting_position(), fn
        {from, to}, position ->
          {:ok, next_position} = Position.apply_move(position, Move.new(from, to))
          next_position
      end)

    verify!([mate])

    if candidate_suffix(mate) != "#" do
      raise "Fool's Mate did not produce checkmate suffix"
    end
  end

  defp measure(positions, repetitions, suffix_fun) do
    :erlang.garbage_collect()

    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, total ->
        Enum.reduce(positions, total, fn position, count ->
          case suffix_fun.(position) do
            "" -> count
            "+" -> count + 1
            "#" -> count + 2
          end
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

  defp ms(microseconds) do
    :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
  end
end

Analysis.SanCheckSuffixComparison.run()
