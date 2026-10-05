alias Analysis.PgnImportPhaseProfile, as: Profile

Logger.configure(level: :warning)

defmodule Analysis.PgnImportPhaseProfile do
  @moduledoc false

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnImporter
  alias Chess.Notation.SAN
  alias Chess.Position
  alias OpenChessLab.Repo

  @unique_game_plies 4

  def build_fixture(path, game_count, :duplicate) do
    File.open!(
      path,
      [:write, :utf8],
      fn io ->
        Enum.each(
          1..game_count,
          fn index ->
            write_game(
              io,
              index,
              "1. e4 e5 2. Nf3 Nc6 *"
            )
          end
        )
      end
    )

    File.stat!(path).size
  end

  def build_fixture(path, game_count, :unique) do
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

  def profile_parse(pgn, game_count) do
    {elapsed_seconds, result} =
      measure(fn ->
        PgnBatchImporter.parse(pgn)
      end)

    parsed_games =
      case result do
        {:ok, parsed_games}
        when length(parsed_games) == game_count ->
          parsed_games

        {:ok, parsed_games} ->
          raise """
          parse phase expected #{game_count} games,
          got #{length(parsed_games)}
          """

        {:error, reason} ->
          raise """
          parse phase failed:
          #{inspect(reason)}
          """
      end

    %{
      elapsed_seconds: elapsed_seconds,
      parsed_games: parsed_games
    }
  end

  def profile_persist(parsed_games, run_id) do
    game_count =
      length(parsed_games)

    {elapsed_seconds, imported_count} =
      measure(fn ->
        parsed_games
        |> Enum.with_index(1)
        |> Enum.reduce_while(
          0,
          fn {parsed, index}, imported_count ->
            case PgnImporter.import_parsed(
                   record_id(
                     "persist",
                     run_id,
                     index
                   ),
                   parsed
                 ) do
              {:ok, _record} ->
                {:cont, imported_count + 1}

              {:error, reason} ->
                raise """
                persist phase failed at game #{index}:
                #{inspect(reason)}
                """
            end
          end
        )
      end)

    if imported_count != game_count do
      raise """
      persist phase expected #{game_count} games,
      got #{imported_count}
      """
    end

    %{
      elapsed_seconds: elapsed_seconds
    }
  end

  def profile_file_import(path, game_count, run_id) do
    {elapsed_seconds, result} =
      measure(fn ->
        PgnBatchImporter.import_file(
          path,
          fn index ->
            record_id(
              "end-to-end",
              run_id,
              index
            )
          end
        )
      end)

    case result do
      {:ok, ^game_count} ->
        %{
          elapsed_seconds: elapsed_seconds
        }

      {:ok, imported_count} ->
        raise """
        end-to-end phase expected #{game_count} games,
        got #{imported_count}
        """

      {:error, reason} ->
        raise """
        end-to-end phase failed:
        #{inspect(reason)}
        """
    end
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

  def minimum(values) do
    Enum.min(values)
  end

  def maximum(values) do
    Enum.max(values)
  end

  defp write_game(io, index, movetext) do
    IO.write(
      io,
      """
      [Event "PGN phase profile #{index}"]
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

  defp measure(fun) when is_function(fun, 0) do
    :erlang.garbage_collect()

    started_at =
      System.monotonic_time()

    result =
      fun.()

    finished_at =
      System.monotonic_time()

    elapsed_seconds =
      finished_at
      |> Kernel.-(started_at)
      |> System.convert_time_unit(
        :native,
        :microsecond
      )
      |> Kernel./(1_000_000)

    {
      elapsed_seconds,
      result
    }
  end

  defp record_id(mode, run_id, index) do
    "pgn-phase-profile-#{mode}-#{run_id}-#{index}"
  end
end

_database_url =
  System.get_env("DATABASE_URL") ||
    raise """
    DATABASE_URL is required.

    Use a dedicated benchmark database because this profile
    truncates the OpenChessLab PostgreSQL tables.

    Example:

        ecto://openchesslab:openchesslab@localhost/openchesslab_bench
    """

game_count =
  System.get_env(
    "PGN_IMPORT_PHASE_GAMES",
    "1000"
  )
  |> String.to_integer()

run_count =
  System.get_env(
    "PGN_IMPORT_PHASE_RUNS",
    "3"
  )
  |> String.to_integer()

fixture_mode =
  case System.get_env(
         "PGN_IMPORT_PHASE_FIXTURE",
         "duplicate"
       ) do
    "duplicate" ->
      :duplicate

    "unique" ->
      :unique

    fixture ->
      raise """
      PGN_IMPORT_PHASE_FIXTURE must be "duplicate" or "unique",
      got #{inspect(fixture)}
      """
  end

if game_count <= 0 do
  raise "PGN_IMPORT_PHASE_GAMES must be positive"
end

if run_count <= 0 do
  raise "PGN_IMPORT_PHASE_RUNS must be positive"
end

path =
  Path.join(
    System.tmp_dir!(),
    "openchesslab-pgn-import-phase-profile-#{System.unique_integer([:positive])}.pgn"
  )

try do
  IO.puts("""
  Building PGN import phase-profile fixture...

  games:   #{game_count}
  runs:    #{run_count}
  fixture: #{fixture_mode}
  """)

  file_size =
    Profile.build_fixture(
      path,
      game_count,
      fixture_mode
    )

  pgn =
    File.read!(path)

  IO.puts("""
  fixture size: #{Profile.format_bytes(file_size)}

  Profiling without PostgreSQL query telemetry...
  """)

  results =
    Enum.map(
      1..run_count,
      fn run ->
        run_id =
          Base.url_encode64(
            :crypto.strong_rand_bytes(8),
            padding: false
          )

        :ok =
          Profile.cleanup()

        end_to_end =
          Profile.profile_file_import(
            path,
            game_count,
            run_id
          )

        parse =
          Profile.profile_parse(
            pgn,
            game_count
          )

        :ok =
          Profile.cleanup()

        persist =
          Profile.profile_persist(
            parse.parsed_games,
            run_id
          )

        result = %{
          run: run,
          parse_seconds: parse.elapsed_seconds,
          persist_seconds: persist.elapsed_seconds,
          end_to_end_seconds: end_to_end.elapsed_seconds
        }

        IO.puts("""
        Run #{run}:
          parse only:   #{Profile.format_seconds(result.parse_seconds)} | #{Profile.format_rate(game_count, result.parse_seconds)}
          persist only: #{Profile.format_seconds(result.persist_seconds)} | #{Profile.format_rate(game_count, result.persist_seconds)}
          end-to-end:   #{Profile.format_seconds(result.end_to_end_seconds)} | #{Profile.format_rate(game_count, result.end_to_end_seconds)}
        """)

        result
      end
    )

  parse_times =
    Enum.map(
      results,
      & &1.parse_seconds
    )

  persist_times =
    Enum.map(
      results,
      & &1.persist_seconds
    )

  end_to_end_times =
    Enum.map(
      results,
      & &1.end_to_end_seconds
    )

  parse_median =
    Profile.median(parse_times)

  persist_median =
    Profile.median(persist_times)

  end_to_end_median =
    Profile.median(end_to_end_times)

  IO.puts("""
  PGN import phase profile

  games:   #{game_count}
  runs:    #{run_count}
  fixture: #{fixture_mode}

  Parse only:
    min:         #{Profile.format_seconds(Profile.minimum(parse_times))}
    median:      #{Profile.format_seconds(parse_median)}
    max:         #{Profile.format_seconds(Profile.maximum(parse_times))}
    median rate: #{Profile.format_rate(game_count, parse_median)}

  Persist pre-parsed games:
    min:         #{Profile.format_seconds(Profile.minimum(persist_times))}
    median:      #{Profile.format_seconds(persist_median)}
    max:         #{Profile.format_seconds(Profile.maximum(persist_times))}
    median rate: #{Profile.format_rate(game_count, persist_median)}

  Streaming end-to-end:
    min:         #{Profile.format_seconds(Profile.minimum(end_to_end_times))}
    median:      #{Profile.format_seconds(end_to_end_median)}
    max:         #{Profile.format_seconds(Profile.maximum(end_to_end_times))}
    median rate: #{Profile.format_rate(game_count, end_to_end_median)}
  """)
after
  Profile.cleanup()
  File.rm(path)
end
