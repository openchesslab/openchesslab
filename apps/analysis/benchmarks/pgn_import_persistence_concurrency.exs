alias Analysis.PgnImportPersistenceConcurrency, as: Profile

Logger.configure(level: :warning)

defmodule Analysis.PgnImportPersistenceConcurrency do
  @moduledoc false

  alias Analysis.GameStart
  alias Analysis.PgnImporter
  alias Chess.Position
  alias OpenChessLab.Repo

  @plies_per_game 4

  def build_unique_games(game_count) do
    initial_position =
      Position.starting_position()

    {
      reversed_games,
      remaining
    } =
      collect_games(
        initial_position,
        initial_position,
        @plies_per_game,
        [],
        [],
        [],
        game_count
      )

    if remaining != 0 do
      generated_count =
        game_count - remaining

      raise """
      could generate only #{generated_count} unique #{@plies_per_game}-ply games,
      requested #{game_count}
      """
    end

    reversed_games
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {parsed, index} ->
      %{
        parsed
        | headers: %{
            "Event" => "PGN persistence concurrency #{index}",
            "White" => "Alice",
            "Black" => "Bob",
            "Result" => "*"
          }
      }
    end)
  end

  def profile(parsed_games, concurrency, run) do
    run_id =
      Base.url_encode64(
        :crypto.strong_rand_bytes(8),
        padding: false
      )

    :erlang.garbage_collect()

    started_at =
      System.monotonic_time()

    imported_count =
      parsed_games
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {parsed, index} ->
          record_id =
            record_id(
              concurrency,
              run,
              run_id,
              index
            )

          case PgnImporter.import_parsed(
                 record_id,
                 parsed
               ) do
            {:ok, _record} ->
              :ok

            {:error, reason} ->
              {:error,
               {
                 index,
                 reason
               }}
          end
        end,
        max_concurrency: concurrency,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce(
        0,
        fn
          {:ok, :ok}, imported_count ->
            imported_count + 1

          {:ok,
           {
             :error,
             {
               index,
               reason
             }
           }},
          _imported_count ->
            raise """
            persistence failed at game #{index}:
            #{inspect(reason)}
            """

          {:exit, reason}, _imported_count ->
            raise """
            persistence task exited:
            #{inspect(reason)}
            """
        end
      )

    finished_at =
      System.monotonic_time()

    expected_count =
      length(parsed_games)

    if imported_count != expected_count do
      raise """
      expected #{expected_count} imported games,
      got #{imported_count}
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

    validate_database!(expected_count)

    elapsed_seconds
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

  def format_seconds(seconds) do
    "#{Float.round(seconds, 3)} s"
  end

  def format_rate(game_count, seconds) do
    "#{Float.round(game_count / seconds, 1)} games/s"
  end

  def format_speedup(baseline, elapsed) do
    "#{Float.round(baseline / elapsed, 2)}x"
  end

  defp collect_games(
         _initial_position,
         _position,
         _plies_remaining,
         _reversed_moves,
         _reversed_replay,
         games,
         0
       ) do
    {
      games,
      0
    }
  end

  defp collect_games(
         initial_position,
         position,
         0,
         reversed_moves,
         reversed_replay,
         games,
         remaining
       ) do
    parsed = %{
      headers: %{},
      initial_position: initial_position,
      start: GameStart.standard(),
      moves: Enum.reverse(reversed_moves),
      replay: Enum.reverse(reversed_replay),
      final_position: position
    }

    {
      [
        parsed
        | games
      ],
      remaining - 1
    }
  end

  defp collect_games(
         initial_position,
         position,
         plies_remaining,
         reversed_moves,
         reversed_replay,
         games,
         remaining
       ) do
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
              initial_position,
              next_position,
              plies_remaining - 1,
              [
                move
                | reversed_moves
              ],
              [
                {
                  move,
                  next_position
                }
                | reversed_replay
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

  defp validate_database!(game_count) do
    [
      [
        games,
        occurrences,
        records
      ]
    ] =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM games),
          (SELECT count(*) FROM game_occurrences),
          (SELECT count(*) FROM game_records)
        """,
        []
      ).rows

    expected_occurrences =
      game_count *
        (@plies_per_game + 1)

    if games != game_count do
      raise """
      expected #{game_count} canonical games,
      got #{games}
      """
    end

    if occurrences != expected_occurrences do
      raise """
      expected #{expected_occurrences} occurrences,
      got #{occurrences}
      """
    end

    if records != game_count do
      raise """
      expected #{game_count} game records,
      got #{records}
      """
    end

    :ok
  end

  defp record_id(concurrency, run, run_id, index) do
    "pgn-concurrency-#{concurrency}-#{run}-#{run_id}-#{index}"
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database because this profile
    truncates the OpenChessLab PostgreSQL tables.
    """

game_count =
  System.get_env(
    "PGN_IMPORT_CONCURRENCY_GAMES",
    "1000"
  )
  |> String.to_integer()

run_count =
  System.get_env(
    "PGN_IMPORT_CONCURRENCY_RUNS",
    "5"
  )
  |> String.to_integer()

concurrencies =
  System.get_env(
    "PGN_IMPORT_CONCURRENCIES",
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
  raise "PGN_IMPORT_CONCURRENCY_GAMES must be positive"
end

if run_count <= 0 do
  raise "PGN_IMPORT_CONCURRENCY_RUNS must be positive"
end

if concurrencies == [] or
     Enum.any?(
       concurrencies,
       &(&1 <= 0)
     ) do
  raise """
  PGN_IMPORT_CONCURRENCIES must contain positive integers
  """
end

pool_size =
  OpenChessLab.Repo.config()
  |> Keyword.get(
    :pool_size,
    10
  )

IO.puts("""
Building unique pre-parsed games...

games:         #{game_count}
runs:          #{run_count}
concurrencies: #{Enum.join(concurrencies, ", ")}
repo pool:     #{pool_size}
""")

parsed_games =
  Profile.build_unique_games(game_count)

IO.puts("""
Profiling durable per-game persistence...

Each worker still calls PgnImporter.import_parsed/2.
Every game therefore retains its own PostgreSQL transaction.
""")

try do
  results =
    Enum.map(
      concurrencies,
      fn concurrency ->
        times =
          Enum.map(
            1..run_count,
            fn run ->
              :ok =
                Profile.cleanup()

              elapsed =
                Profile.profile(
                  parsed_games,
                  concurrency,
                  run
                )

              IO.puts(
                "concurrency #{concurrency}, " <>
                  "run #{run}: " <>
                  "#{Profile.format_seconds(elapsed)} | " <>
                  "#{Profile.format_rate(game_count, elapsed)}"
              )

              elapsed
            end
          )

        median =
          Profile.median(times)

        %{
          concurrency: concurrency,
          median: median,
          minimum: Enum.min(times),
          maximum: Enum.max(times)
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

  PGN persistence concurrency profile

  games: #{game_count}
  runs:  #{run_count}
  """)

  Enum.each(
    results,
    fn result ->
      speedup =
        if baseline do
          Profile.format_speedup(
            baseline,
            result.median
          )
        else
          "n/a"
        end

      IO.puts("""
      concurrency #{result.concurrency}:
        min:         #{Profile.format_seconds(result.minimum)}
        median:      #{Profile.format_seconds(result.median)}
        max:         #{Profile.format_seconds(result.maximum)}
        median rate: #{Profile.format_rate(game_count, result.median)}
        speedup:     #{speedup}
      """)
    end
  )
after
  Profile.cleanup()
end
