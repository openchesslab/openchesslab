# Profiles deterministic, legal PGN parsing using Erlang VM call-time counters.
# Does not depend on the optional OTP tools application (tprof/fprof).
# No database is started or accessed.
# Run from the OpenChessLab repository root:
#   mix run --no-start apps/analysis/benchmarks/pgn_import_parse_call_time.exs

alias Analysis.PgnLongGameFixture
alias Analysis.PgnParseCallTimeProfile, as: Profile

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.PgnParseCallTimeProfile do
  @moduledoc false

  alias Analysis.PgnBatchImporter

  def parse!(pgn, expected_count) do
    case PgnBatchImporter.parse(pgn) do
      {:ok, games} when length(games) == expected_count ->
        :ok

      other ->
        raise "Unexpected PGN parse result: #{inspect(other)}"
    end
  end

  def call_time(pgn, expected_count) do
    # Run the parser first, so the application modules it calls are loaded.
    parse!(pgn, expected_count)

    functions =
      :code.all_loaded()
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&application_module?/1)
      |> Enum.flat_map(&module_functions/1)
      |> Enum.uniq()

    if functions == [] do
      raise "No Chess/Analysis BEAM functions found to profile"
    end

    IO.puts("Tracing #{length(functions)} Chess/Analysis BEAM functions...")

    # Trace one process only. The benchmark uses a sequential parse.
    # Function counters are read before disabling their trace patterns.
    try do
      Enum.each(functions, fn mfa ->
        :erlang.trace_pattern(mfa, true, [:call_time])
      end)

      try do
        :erlang.trace(self(), true, [:call])
        parse!(pgn, expected_count)
      after
        :erlang.trace(self(), false, [:call])
      end

      pid = self()

      functions
      |> Enum.flat_map(fn {module, function, arity} = mfa ->
        case :erlang.trace_info(mfa, :call_time) do
          {:call_time, readings} when is_list(readings) ->
            {calls, microseconds} =
              Enum.reduce(readings, {0, 0}, fn
                {^pid, count, seconds, micros}, {sum_count, sum_us} ->
                  {sum_count + count, sum_us + seconds * 1_000_000 + micros}

                _other, acc ->
                  acc
              end)

            if calls > 0 do
              [{module, function, arity, calls, microseconds}]
            else
              []
            end

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn {_module, _function, _arity, _calls, us} -> -us end)
    after
      # Always clear VM-wide function trace patterns, even on parse errors.
      :erlang.trace(self(), false, [:call])

      Enum.each(functions, fn mfa ->
        :erlang.trace_pattern(mfa, false, [:call_time])
      end)
    end
  end

  defp application_module?(module) do
    name = Atom.to_string(module)

    String.starts_with?(name, "Elixir.Chess.") or
      String.starts_with?(name, "Elixir.Analysis.")
  end

  defp module_functions(module) do
    beam_path = :code.which(module)

    members =
      if is_list(beam_path) do
        case :beam_lib.chunks(beam_path, [:exports, :locals]) do
          {:ok, {^module, chunks}} ->
            Enum.flat_map(chunks, fn {_kind, entries} -> entries end)

          _other ->
            module.module_info(:functions)
        end
      else
        module.module_info(:functions)
      end

    Enum.map(members, fn {function, arity} -> {module, function, arity} end)
  end
end

game_count = System.get_env("PGN_PARSE_TPROF_GAMES", "20") |> String.to_integer()
plies = System.get_env("PGN_PARSE_TPROF_PLIES", "80") |> String.to_integer()

duplicate_percent =
  System.get_env("PGN_PARSE_TPROF_DUPLICATE_PERCENT", "0") |> String.to_integer()

if game_count <= 0 or plies < 2 or plies > 120 or
     duplicate_percent < 0 or duplicate_percent >= 100 do
  raise ArgumentError, "expected games > 0, plies 2..120, duplicates 0..99"
end

path =
  Path.join(
    System.tmp_dir!(),
    "openchesslab-parse-call-time-#{System.unique_integer([:positive])}.pgn"
  )

try do
  bytes = PgnLongGameFixture.build_fixture(path, game_count, plies, duplicate_percent)
  pgn = File.read!(path)

  {unprofiled_us, :ok} = :timer.tc(fn -> Profile.parse!(pgn, game_count) end)

  IO.puts("""
  PGN parsing function profile (Erlang VM call_time)

  games:         #{game_count}
  plies/game:    #{plies}
  duplicates:    #{duplicate_percent}%
  fixture bytes: #{bytes}
  unprofiled:    #{Float.round(unprofiled_us / 1_000_000, 3)} s

  Profiling call time (tracing changes execution speed)...
  """)

  rows = Profile.call_time(pgn, game_count)

  if rows == [] do
    raise "No call-time samples collected; verify tracing support in this Erlang runtime"
  end

  IO.puts("Top 40 functions by accumulated call time:")

  IO.puts(
    String.pad_trailing("FUNCTION", 68) <>
      String.pad_leading("CALLS", 12) <>
      String.pad_leading("TIME (ms)", 14)
  )

  rows
  |> Enum.take(40)
  |> Enum.each(fn {module, function, arity, calls, us} ->
    name = "#{inspect(module)}.#{function}/#{arity}"

    IO.puts(
      String.pad_trailing(name, 68) <>
        String.pad_leading(Integer.to_string(calls), 12) <>
        String.pad_leading(:erlang.float_to_binary(us / 1_000, decimals: 2), 14)
    )
  end)

  IO.puts("""

  Times are instrumentation-affected call_time counters for the current process.
  Only Chess.* and Analysis.* functions are individually traced; time spent in
  untraced callees may be attributed to the calling traced function.
  """)
after
  File.rm(path)
end
