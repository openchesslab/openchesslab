alias Analysis.PgnBatchImportBenchmark, as: Benchmark

Logger.configure(level: :warning)

defmodule Analysis.PgnBatchImportBenchmark do
  @moduledoc false

  alias Analysis.PgnBatchImporter
  alias OpenChessLab.Repo

  def build_fixture(path, game_count) do
    File.open!(
      path,
      [:write, :utf8],
      fn io ->
        Enum.each(
          1..game_count,
          fn index ->
            IO.write(
              io,
              """
              [Event "PGN import benchmark #{index}"]
              [White "Alice"]
              [Black "Bob"]
              [Result "*"]

              1. e4 e5 2. Nf3 Nc6 *

              """
            )
          end
        )
      end
    )

    File.stat!(path).size
  end

  def bounded_import(path, game_count, run_id, sample_interval) do
    pgn =
      File.read!(path)

    record_ids =
      Enum.map(
        1..game_count,
        fn index ->
          record_id(
            "bounded",
            run_id,
            index
          )
        end
      )

    measure(
      fn ->
        case PgnBatchImporter.import_games(
               record_ids,
               pgn
             ) do
          {:ok, records}
          when length(records) == game_count ->
            :ok

          {:ok, records} ->
            raise """
            bounded import expected #{game_count} records,
            got #{length(records)}
            """

          {:error, reason} ->
            raise """
            bounded import failed:
            #{inspect(reason)}
            """
        end
      end,
      sample_interval
    )
  end

  def file_import(path, game_count, run_id, sample_interval) do
    measure(
      fn ->
        case PgnBatchImporter.import_file(
               path,
               fn index ->
                 record_id(
                   "stream",
                   run_id,
                   index
                 )
               end
             ) do
          {:ok, ^game_count} ->
            :ok

          {:ok, imported_count} ->
            raise """
            streaming import expected #{game_count} records,
            got #{imported_count}
            """

          {:error, reason} ->
            raise """
            streaming import failed:
            #{inspect(reason)}
            """
        end
      end,
      sample_interval
    )
  end

  def cleanup do
    Repo.query!(
      """
      TRUNCATE TABLE
        analyses,
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes >= 1024 * 1024 * 1024 ->
        "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GiB"

      bytes >= 1024 * 1024 ->
        "#{Float.round(bytes / (1024 * 1024), 2)} MiB"

      bytes >= 1024 ->
        "#{Float.round(bytes / 1024, 2)} KiB"

      true ->
        "#{bytes} B"
    end
  end

  def format_seconds(seconds) do
    "#{Float.round(seconds, 3)} s"
  end

  def format_rate(game_count, seconds) do
    rate =
      game_count /
        seconds

    "#{Float.round(rate, 1)} games/s"
  end

  defp measure(fun, sample_interval) when is_function(fun, 0) do
    :erlang.garbage_collect()

    baseline_memory =
      :erlang.memory(:total)

    parent =
      self()

    ref =
      make_ref()

    sampler =
      spawn_link(fn ->
        sample_memory(
          parent,
          ref,
          baseline_memory,
          sample_interval
        )
      end)

    started_at =
      System.monotonic_time()

    result =
      fun.()

    finished_at =
      System.monotonic_time()

    send(
      sampler,
      {
        :stop,
        ref
      }
    )

    peak_memory =
      receive do
        {
          :memory_peak,
          ^ref,
          memory
        } ->
          memory
      after
        5_000 ->
          raise "memory sampler did not stop"
      end

    elapsed_seconds =
      finished_at
      |> Kernel.-(started_at)
      |> System.convert_time_unit(
        :native,
        :microsecond
      )
      |> Kernel./(1_000_000)

    %{
      result: result,
      elapsed_seconds: elapsed_seconds,
      baseline_memory: baseline_memory,
      peak_memory: peak_memory,
      peak_growth:
        max(
          peak_memory - baseline_memory,
          0
        )
    }
  end

  defp sample_memory(parent, ref, peak_memory, sample_interval) do
    receive do
      {
        :stop,
        ^ref
      } ->
        final_memory =
          :erlang.memory(:total)

        send(
          parent,
          {
            :memory_peak,
            ref,
            max(
              peak_memory,
              final_memory
            )
          }
        )
    after
      sample_interval ->
        current_memory =
          :erlang.memory(:total)

        sample_memory(
          parent,
          ref,
          max(
            peak_memory,
            current_memory
          ),
          sample_interval
        )
    end
  end

  defp record_id(mode, run_id, index) do
    "pgn-import-bench-#{mode}-#{run_id}-#{index}"
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database because this benchmark
    truncates the OpenChessLab PostgreSQL tables.

    Example:

        ecto://openchesslab:openchesslab@localhost/openchesslab_bench
    """

game_count =
  System.get_env(
    "PGN_IMPORT_BENCH_GAMES",
    "1000"
  )
  |> String.to_integer()

sample_interval =
  System.get_env(
    "PGN_IMPORT_BENCH_MEMORY_SAMPLE_MS",
    "5"
  )
  |> String.to_integer()

if game_count <= 0 do
  raise "PGN_IMPORT_BENCH_GAMES must be positive"
end

if sample_interval <= 0 do
  raise """
  PGN_IMPORT_BENCH_MEMORY_SAMPLE_MS must be positive
  """
end

path =
  Path.join(
    System.tmp_dir!(),
    "openchesslab-pgn-import-benchmark-#{System.unique_integer([:positive])}.pgn"
  )

run_id =
  Base.url_encode64(
    :crypto.strong_rand_bytes(8),
    padding: false
  )

try do
  IO.puts("""
  Building PGN batch-import benchmark fixture...

  games: #{game_count}
  """)

  file_size =
    Benchmark.build_fixture(
      path,
      game_count
    )

  IO.puts("""
  fixture size: #{Benchmark.format_bytes(file_size)}
  memory sampling interval: #{sample_interval} ms

  Running bounded in-memory import...
  """)

  :ok =
    Benchmark.cleanup()

  bounded =
    Benchmark.bounded_import(
      path,
      game_count,
      run_id,
      sample_interval
    )

  IO.puts("""
  Bounded import complete.

  Running streaming file import...
  """)

  :ok =
    Benchmark.cleanup()

  streamed =
    Benchmark.file_import(
      path,
      game_count,
      run_id,
      sample_interval
    )

  bounded_rate =
    Benchmark.format_rate(
      game_count,
      bounded.elapsed_seconds
    )

  streamed_rate =
    Benchmark.format_rate(
      game_count,
      streamed.elapsed_seconds
    )

  IO.puts("""
  PGN batch-import benchmark

  games:        #{game_count}
  fixture size: #{Benchmark.format_bytes(file_size)}

  Bounded in-memory import:
    elapsed:       #{Benchmark.format_seconds(bounded.elapsed_seconds)}
    throughput:    #{bounded_rate}
    baseline BEAM: #{Benchmark.format_bytes(bounded.baseline_memory)}
    peak BEAM:     #{Benchmark.format_bytes(bounded.peak_memory)}
    peak growth:   #{Benchmark.format_bytes(bounded.peak_growth)}

  Streaming file import:
    elapsed:       #{Benchmark.format_seconds(streamed.elapsed_seconds)}
    throughput:    #{streamed_rate}
    baseline BEAM: #{Benchmark.format_bytes(streamed.baseline_memory)}
    peak BEAM:     #{Benchmark.format_bytes(streamed.peak_memory)}
    peak growth:   #{Benchmark.format_bytes(streamed.peak_growth)}
  """)
after
  Benchmark.cleanup()
  File.rm(path)
end
