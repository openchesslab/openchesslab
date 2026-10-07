alias Analysis.PgnImportParallelFileBenchmark, as: Benchmark

Logger.configure(level: :warning)

defmodule Analysis.PgnImportParallelFileBenchmark do
  @moduledoc false

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnBatchImporter.ParallelImportResult
  alias Chess.Notation.SAN
  alias Chess.Position
  alias OpenChessLab.Repo

  @unique_game_plies 4

  def build_fixture(path, game_count) do
    movetexts =
      unique_movetexts(game_count)

    File.open!(
      path,
      [:write, :utf8],
      fn io ->
        movetexts
        |> Enum.with_index(1)
        |> Enum.each(fn {movetext, index} ->
          write_game(
            io,
            index,
            movetext
          )
        end)
      end
    )

    File.stat!(path).size
  end

  def profile(path, game_count, concurrency, run) do
    run_id =
      Base.url_encode64(
        :crypto.strong_rand_bytes(8),
        padding: false
      )

    :erlang.garbage_collect()

    started_at =
      System.monotonic_time()

    result =
      PgnBatchImporter.import_file_parallel(
        path,
        fn index ->
          record_id(
            concurrency,
            run,
            run_id,
            index
          )
        end,
        concurrency
      )

    finished_at =
      System.monotonic_time()

    case result do
      {:ok,
       %ParallelImportResult{
         imported_count: ^game_count,
         failures: []
       }} ->
        :ok

      {:ok, %ParallelImportResult{} = result} ->
        raise """
        expected #{game_count} successful imports and no failures,
        got:

        #{inspect(result, pretty: true)}
        """

      {:error, reason} ->
        raise """
        parallel file import failed:

        #{inspect(reason, pretty: true)}
        """
    end

    elapsed_seconds =
      finished_at
      |> Kernel.-(started_at)
      |> System.convert_time_unit(
        :native,
        :microsecond
      )
      |> Kernel./(1_000_000)

    counts =
      database_counts()

    validate_counts!(
      game_count,
      counts
    )

    %{
      elapsed_seconds: elapsed_seconds,
      counts: counts
    }
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

  def median(values) do
    sorted =
      Enum.sort(values)

    count =
      length(sorted)

    middle =
      div(
        count,
        2
      )

    if rem(count, 2) == 1 do
      Enum.at(
        sorted,
        middle
      )
    else
      (Enum.at(
         sorted,
         middle - 1
       ) +
         Enum.at(
           sorted,
           middle
         )) / 2
    end
  end

  def format_bytes(bytes) do
    cond do
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
    "#{Float.round(game_count / seconds, 1)} games/s"
  end

  def format_speedup(baseline, elapsed) do
    "#{Float.round(baseline / elapsed, 2)}x"
  end

  defp write_game(io, index, movetext) do
    IO.write(
      io,
      """
      [Event "PGN parallel file benchmark #{index}"]
      [White "Alice"]
      [Black "Bob"]
      [Result "*"]

      #{movetext}

      """
    )
  end

  defp unique_movetexts(game_count) do
    {
      reversed_games,
      remaining
    } =
      collect_games(
        Position.starting_position(),
        @unique_game_plies,
        [],
        [],
        game_count
      )

    if remaining != 0 do
      generated_count =
        game_count - remaining

      raise """
      could generate only #{generated_count} unique #{@unique_game_plies}-ply games,
      requested #{game_count}
      """
    end

    reversed_games
    |> Enum.reverse()
    |> Enum.map(&format_movetext/1)
  end

  defp collect_games(_position, _plies_remaining, _reversed_sans, games, 0) do
    {
      games,
      0
    }
  end

  defp collect_games(_position, 0, reversed_sans, games, remaining) do
    {
      [
        Enum.reverse(reversed_sans)
        | games
      ],
      remaining - 1
    }
  end

  defp collect_games(position, plies_remaining, reversed_sans, games, remaining) do
    position
    |> Position.legal_moves()
    |> Enum.reduce_while(
      {
        games,
        remaining
      },
      fn move, {games, remaining} ->
        if remaining == 0 do
          {:halt,
           {
             games,
             remaining
           }}
        else
          {:ok, san} =
            SAN.format(
              position,
              move
            )

          {:ok, next_position} =
            Position.apply_move(
              position,
              move
            )

          {
            games,
            remaining
          } =
            collect_games(
              next_position,
              plies_remaining - 1,
              [
                san
                | reversed_sans
              ],
              games,
              remaining
            )

          if remaining == 0 do
            {:halt,
             {
               games,
               remaining
             }}
          else
            {:cont,
             {
               games,
               remaining
             }}
          end
        end
      end
    )
  end

  defp format_movetext(sans) do
    sans
    |> Enum.chunk_every(2)
    |> Enum.with_index(1)
    |> Enum.map_join(
      " ",
      fn
        {
          [
            white,
            black
          ],
          move_number
        } ->
          "#{move_number}. #{white} #{black}"

        {
          [
            white
          ],
          move_number
        } ->
          "#{move_number}. #{white}"
      end
    )
    |> Kernel.<>(" *")
  end

  defp database_counts do
    [
      [
        positions,
        position_features,
        games,
        occurrences,
        records
      ]
    ] =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM positions),
          (SELECT count(*) FROM position_features),
          (SELECT count(*) FROM games),
          (SELECT count(*) FROM game_occurrences),
          (SELECT count(*) FROM game_records)
        """,
        []
      ).rows

    %{
      positions: positions,
      position_features: position_features,
      games: games,
      occurrences: occurrences,
      records: records
    }
  end

  defp validate_counts!(game_count, counts) do
    expected_occurrences =
      game_count *
        (@unique_game_plies + 1)

    if counts.positions !=
         counts.position_features do
      raise """
      expected one position_features row per position,
      got #{counts.positions} positions and
      #{counts.position_features} position feature rows
      """
    end

    if counts.games !=
         game_count do
      raise """
      expected #{game_count} canonical games,
      got #{counts.games}
      """
    end

    if counts.occurrences !=
         expected_occurrences do
      raise """
      expected #{expected_occurrences} occurrences,
      got #{counts.occurrences}
      """
    end

    if counts.records !=
         game_count do
      raise """
      expected #{game_count} game records,
      got #{counts.records}
      """
    end

    :ok
  end

  defp record_id(concurrency, run, run_id, index) do
    "pgn-parallel-file-#{concurrency}-#{run}-#{run_id}-#{index}"
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database because this benchmark
    truncates the OpenChessLab PostgreSQL tables.
    """

game_count =
  System.get_env(
    "PGN_IMPORT_PARALLEL_GAMES",
    "1000"
  )
  |> String.to_integer()

run_count =
  System.get_env(
    "PGN_IMPORT_PARALLEL_RUNS",
    "5"
  )
  |> String.to_integer()

concurrencies =
  System.get_env(
    "PGN_IMPORT_PARALLEL_CONCURRENCIES",
    "1,2,4,8"
  )
  |> String.split(
    ",",
    trim: true
  )
  |> Enum.map(fn value ->
    value
    |> String.trim()
    |> String.to_integer()
  end)

if game_count <= 0 do
  raise """
  PGN_IMPORT_PARALLEL_GAMES must be positive
  """
end

if run_count <= 0 do
  raise """
  PGN_IMPORT_PARALLEL_RUNS must be positive
  """
end

if concurrencies == [] or
     Enum.any?(
       concurrencies,
       &(&1 <= 0)
     ) do
  raise """
  PGN_IMPORT_PARALLEL_CONCURRENCIES must contain positive integers
  """
end

pool_size =
  OpenChessLab.Repo.config()
  |> Keyword.get(
    :pool_size,
    10
  )

path =
  Path.join(
    System.tmp_dir!(),
    "openchesslab-pgn-parallel-file-#{System.unique_integer([:positive])}.pgn"
  )

try do
  IO.puts("""
  Building unique PGN file fixture...

  games:         #{game_count}
  runs:          #{run_count}
  concurrencies: #{Enum.join(concurrencies, ", ")}
  repo pool:     #{pool_size}
  """)

  file_size =
    Benchmark.build_fixture(
      path,
      game_count
    )

  IO.puts("""
  fixture size: #{Benchmark.format_bytes(file_size)}

  Profiling bounded-parallel file import...

  Timed work includes:
    file reading
    game splitting
    PGN parsing
    SAN parsing
    per-game PostgreSQL persistence
  """)

  results =
    Enum.map(
      concurrencies,
      fn concurrency ->
        runs =
          Enum.map(
            1..run_count,
            fn run ->
              :ok =
                Benchmark.cleanup()

              result =
                Benchmark.profile(
                  path,
                  game_count,
                  concurrency,
                  run
                )

              IO.puts(
                "concurrency #{concurrency}, " <>
                  "run #{run}: " <>
                  "#{Benchmark.format_seconds(result.elapsed_seconds)} | " <>
                  "#{Benchmark.format_rate(game_count, result.elapsed_seconds)}"
              )

              result
            end
          )

        times =
          Enum.map(
            runs,
            & &1.elapsed_seconds
          )

        last_counts =
          runs
          |> List.last()
          |> Map.fetch!(:counts)

        %{
          concurrency: concurrency,
          median: Benchmark.median(times),
          minimum: Enum.min(times),
          maximum: Enum.max(times),
          counts: last_counts
        }
      end
    )

  baseline =
    results
    |> Enum.find(&(&1.concurrency == 1))
    |> case do
      nil ->
        nil

      result ->
        result.median
    end

  IO.puts("""

  Parallel PGN file import profile

  games: #{game_count}
  runs:  #{run_count}
  """)

  Enum.each(
    results,
    fn result ->
      speedup =
        if baseline do
          Benchmark.format_speedup(
            baseline,
            result.median
          )
        else
          "n/a"
        end

      IO.puts("""
      concurrency #{result.concurrency}:
        min:         #{Benchmark.format_seconds(result.minimum)}
        median:      #{Benchmark.format_seconds(result.median)}
        max:         #{Benchmark.format_seconds(result.maximum)}
        median rate: #{Benchmark.format_rate(game_count, result.median)}
        speedup:     #{speedup}
      """)
    end
  )

  counts =
    results
    |> List.last()
    |> Map.fetch!(:counts)

  IO.puts("""
  Durable rows after a run:
    positions:         #{counts.positions}
    position features: #{counts.position_features}
    canonical games:   #{counts.games}
    occurrences:       #{counts.occurrences}
    game records:      #{counts.records}
  """)
after
  Benchmark.cleanup()
  File.rm(path)
end
