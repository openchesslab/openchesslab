alias Analysis.PgnImportQueryProfile, as: Profile

Logger.configure(level: :warning)

defmodule Analysis.PgnImportQueryProfile do
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
              [Event "PGN query profile #{index}"]
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

  def profile_file_import(path, game_count, run_id) do
    table =
      :ets.new(
        __MODULE__,
        [
          :set,
          :public,
          {
            :write_concurrency,
            true
          }
        ]
      )

    telemetry_event =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)
      |> Kernel.++([:query])

    handler_id =
      {
        __MODULE__,
        self(),
        make_ref()
      }

    :ok =
      :telemetry.attach(
        handler_id,
        telemetry_event,
        &__MODULE__.handle_query/4,
        table
      )

    started_at =
      System.monotonic_time()

    try do
      case PgnBatchImporter.import_file(
             path,
             fn index ->
               record_id(
                 run_id,
                 index
               )
             end
           ) do
        {:ok, ^game_count} ->
          :ok

        {:ok, imported_count} ->
          raise """
          expected #{game_count} imported games,
          got #{imported_count}
          """

        {:error, reason} ->
          raise """
          streaming PGN import failed:
          #{inspect(reason)}
          """
      end

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

      query_profile =
        query_profile(table)

      Map.put(
        query_profile,
        :elapsed_seconds,
        elapsed_seconds
      )
    after
      :telemetry.detach(handler_id)
      :ets.delete(table)
    end
  end

  def handle_query(_event, measurements, metadata, table) do
    total_time =
      Map.get(
        measurements,
        :total_time,
        0
      )

    query_time =
      Map.get(
        measurements,
        :query_time,
        0
      )

    queue_time =
      Map.get(
        measurements,
        :queue_time,
        0
      )

    decode_time =
      Map.get(
        measurements,
        :decode_time,
        0
      )

    :ets.update_counter(
      table,
      :totals,
      [
        {
          2,
          1
        },
        {
          3,
          total_time
        },
        {
          4,
          query_time
        },
        {
          5,
          queue_time
        },
        {
          6,
          decode_time
        }
      ],
      {
        :totals,
        0,
        0,
        0,
        0,
        0
      }
    )

    query =
      Map.get(
        metadata,
        :query,
        "<unknown query>"
      )

    :ets.update_counter(
      table,
      {
        :query,
        query
      },
      [
        {
          2,
          1
        },
        {
          3,
          total_time
        },
        {
          4,
          query_time
        }
      ],
      {
        {
          :query,
          query
        },
        0,
        0,
        0
      }
    )

    :ok
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

  def format_milliseconds(native_time) do
    milliseconds =
      native_time
      |> System.convert_time_unit(
        :native,
        :microsecond
      )
      |> Kernel./(1_000)

    "#{Float.round(milliseconds, 1)} ms"
  end

  def format_rate(game_count, seconds) do
    "#{Float.round(game_count / seconds, 1)} games/s"
  end

  def format_queries_per_game(query_count, game_count) do
    "#{Float.round(query_count / game_count, 2)}"
  end

  def format_percentage(native_time, elapsed_seconds) do
    seconds =
      native_time
      |> System.convert_time_unit(
        :native,
        :microsecond
      )
      |> Kernel./(1_000_000)

    percentage =
      if elapsed_seconds > 0 do
        seconds /
          elapsed_seconds *
          100
      else
        0.0
      end

    "#{Float.round(percentage, 1)}%"
  end

  def query_label(query) do
    query
    |> to_string()
    |> String.replace(
      ~r/\s+/,
      " "
    )
    |> String.trim()
    |> truncate(140)
  end

  defp query_profile(table) do
    [
      {
        :totals,
        query_count,
        total_time,
        query_time,
        queue_time,
        decode_time
      }
    ] =
      :ets.lookup(
        table,
        :totals
      )

    queries =
      table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {
          {
            :query,
            query
          },
          count,
          query_total_time,
          query_execution_time
        } ->
          [
            %{
              query: query,
              count: count,
              total_time: query_total_time,
              query_time: query_execution_time
            }
          ]

        {
          :totals,
          _count,
          _total_time,
          _query_time,
          _queue_time,
          _decode_time
        } ->
          []
      end)
      |> Enum.sort_by(
        & &1.count,
        :desc
      )

    %{
      query_count: query_count,
      total_time: total_time,
      query_time: query_time,
      queue_time: queue_time,
      decode_time: decode_time,
      queries: queries
    }
  end

  defp truncate(value, maximum_length) do
    if String.length(value) <= maximum_length do
      value
    else
      String.slice(
        value,
        0,
        maximum_length - 3
      ) <> "..."
    end
  end

  defp record_id(run_id, index) do
    "pgn-query-profile-#{run_id}-#{index}"
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
    "PGN_IMPORT_PROFILE_GAMES",
    "1000"
  )
  |> String.to_integer()

if game_count <= 0 do
  raise "PGN_IMPORT_PROFILE_GAMES must be positive"
end

path =
  Path.join(
    System.tmp_dir!(),
    "openchesslab-pgn-query-profile-#{System.unique_integer([:positive])}.pgn"
  )

run_id =
  Base.url_encode64(
    :crypto.strong_rand_bytes(8),
    padding: false
  )

try do
  :ok =
    Profile.cleanup()

  IO.puts("""
  Building PGN import query-profile fixture...

  games: #{game_count}
  """)

  file_size =
    Profile.build_fixture(
      path,
      game_count
    )

  IO.puts("""
  fixture size: #{Profile.format_bytes(file_size)}

  Profiling streaming durable import...
  """)

  result =
    Profile.profile_file_import(
      path,
      game_count,
      run_id
    )

  IO.puts("""
  PGN import PostgreSQL query profile

  games:          #{game_count}
  elapsed:        #{Profile.format_seconds(result.elapsed_seconds)}
  throughput:     #{Profile.format_rate(game_count, result.elapsed_seconds)}

  PostgreSQL/Ecto:
    queries:       #{result.query_count}
    queries/game:  #{Profile.format_queries_per_game(result.query_count, game_count)}
    total time:    #{Profile.format_milliseconds(result.total_time)}
    query time:    #{Profile.format_milliseconds(result.query_time)}
    queue time:    #{Profile.format_milliseconds(result.queue_time)}
    decode time:   #{Profile.format_milliseconds(result.decode_time)}
    DB/wall:       #{Profile.format_percentage(result.total_time, result.elapsed_seconds)}

  Query shapes by count:
  """)

  Enum.each(
    result.queries,
    fn query ->
      IO.puts(
        "  #{query.count}x | " <>
          "#{Profile.format_milliseconds(query.total_time)} total | " <>
          "#{Profile.query_label(query.query)}"
      )
    end
  )
after
  Profile.cleanup()
  File.rm(path)
end
