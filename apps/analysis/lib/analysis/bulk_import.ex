defmodule Analysis.BulkImport do
  @moduledoc """
  Streaming bulk import of external PGN dumps into the canonical corpus.

  Built for the lichess open database (`database.lichess.org`), released
  under CC0. A `curl | zstd -dc` pipeline writes into a FIFO, so the reader
  has real backpressure and memory stays bounded for files of any size; the
  downloader's exit status lands in a status file so a stream that ends
  early is reported honestly instead of looking like a complete file.

  Game headers are filtered — both players at the rating floor, no bullet —
  **before** moves are parsed, so rejected games never reach the parser.
  Kept games are persisted with the **grouped** importer by default
  (`PgnBatchImporter.import_stream/3`, batches of ten): one transaction and
  one shared position batch per group, which keeps the load on a small
  managed PostgreSQL instance sane. `mode: :parallel` selects the
  per-game-transaction parallel importer instead.

  The run is resumable and restart-safe: `:skip` discards input games
  during the header scan, and `:record_id_offset` continues the record-id
  sequence where a previous run stopped, so a resumed run neither collides
  with nor duplicates already-imported games. Exceptions inside the
  importer are captured and reported as an error summary instead of
  crashing the evaluation (a crashing worker previously restarted into a
  duplicate-failing rerun).

  The function starts its own applications, so it works both from
  `mix run -e "Analysis.BulkImport.run(...)"` (development) and from
  `/app/bin/openchesslab eval "Analysis.BulkImport.run(...)"` (release
  machines).
  """

  alias Analysis.PgnBatchImporter

  require Logger

  @header_line_regex ~r/^\s*\[[A-Za-z0-9_]+\s+"(?:\\.|[^"])*"\]\s*$/
  @tag_regex ~r/^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$/
  @flush :bulk_import_flush

  @type summary :: %{
          read: non_neg_integer(),
          kept: non_neg_integer(),
          skipped: non_neg_integer(),
          malformed_lines: non_neg_integer(),
          handed: non_neg_integer(),
          imported: non_neg_integer() | nil,
          failure_count: non_neg_integer(),
          import_failures: list(),
          error: term() | nil,
          elapsed_ms: non_neg_integer(),
          rate_per_second: float() | nil,
          source: term()
        }

  @doc """
  Runs a bulk import.

  Options:

    * `:url` — zstd-compressed PGN dump URL (required unless `:path` is given)
    * `:path` — local plain-PGN file instead of a URL
    * `:min_rating` — both players must be at least this Elo (default 2200)
    * `:skip` — input games to discard before importing (default 0)
    * `:limit` — stop after reading this many input games (default: no limit)
    * `:record_id_prefix` — record id prefix (default: derived from the source name)
    * `:record_id_offset` — added to the kept-game index in record ids; use the
      previous run's kept count to resume without collisions (default 0)
    * `:mode` — `:grouped` (default; batches of ten, one transaction per group)
      or `:parallel` (per-game transactions, bounded window)
    * `:batch_size` — grouped mode batch size, 2..10 (default 10)
    * `:concurrency` / `:window` — parallel mode workers and window (defaults 4 / `concurrency * 2`)
    * `:progress_every` — log progress every N input games (default 100_000)
  """
  @spec run(keyword()) :: {:ok, summary()} | {:error, term(), summary()}
  def run(opts) do
    {:ok, _apps} = Application.ensure_all_started(:analysis)

    started = System.monotonic_time(:millisecond)
    source = prepare_source!(opts)
    prefix = Keyword.get(opts, :record_id_prefix) || default_prefix(source)
    offset = Keyword.get(opts, :record_id_offset, 0)
    limit = Keyword.get(opts, :limit)

    {:ok, stats} =
      Agent.start_link(fn -> %{read: 0, kept: 0, skipped: 0, malformed: 0, handed: 0} end)

    recorded_id = fn index ->
      Agent.update(stats, fn counts -> %{counts | handed: counts.handed + 1} end)
      "#{prefix}-#{offset + index}"
    end

    lines =
      filter_lines(source.lines,
        min_rating: Keyword.get(opts, :min_rating, 2200),
        skip: Keyword.get(opts, :skip, 0),
        limit: limit,
        progress_every: Keyword.get(opts, :progress_every, 100_000),
        stats: stats,
        started: started
      )

    result = import_lines(lines, opts, recorded_id)
    counts = Agent.get(stats, & &1)
    Agent.stop(stats)
    elapsed_ms = System.monotonic_time(:millisecond) - started
    limited? = limit != nil and counts.read >= limit
    source_status = source.finish.(limited?)
    summary = build_summary(counts, result, elapsed_ms, source_status)

    case {result, source_status} do
      {{:ok, _}, :ok} ->
        Logger.info("bulk import finished: #{inspect(Map.delete(summary, :import_failures))}")
        {:ok, summary}

      {{:ok, _}, {:source_failed, code}} ->
        Logger.error("bulk import: source stream failed (exit #{inspect(code)})")
        {:error, {:source, code}, summary}

      {{:error, reason}, _} ->
        Logger.error("bulk import aborted: #{inspect(reason)}")
        {:error, reason, summary}
    end
  end

  # The importer call itself is wrapped so a raised database/checkout error
  # ends the run with an honest summary instead of crashing the evaluation.
  defp import_lines(lines, opts, recorded_id) do
    case Keyword.get(opts, :mode, :grouped) do
      :grouped ->
        batch_size = Keyword.get(opts, :batch_size, 10)

        case PgnBatchImporter.import_stream(lines, recorded_id, batch_size) do
          {:ok, imported} -> {:ok, %{imported_count: imported, failures: []}}
          {:error, reason} -> {:error, reason}
        end

      :parallel ->
        concurrency = Keyword.get(opts, :concurrency, 4)
        window = Keyword.get(opts, :window, concurrency * 2)
        PgnBatchImporter.import_stream_parallel(lines, recorded_id, concurrency, window)
    end
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  catch
    kind, value -> {:error, {:caught, kind, inspect(value)}}
  end

  @doc """
  Lazily filters a PGN line stream to the games that pass the header filter.

  Games are recognised exactly like `PgnBatchImporter` recognises them: a
  game starts at a header line, and a new header line closes the previous
  one. Only the header block decides; moves are never inspected, so rejected
  games never reach the parser. When `:stats` names an Agent, per-input-game
  counts (`read/kept/skipped/malformed`) land there as the stream advances;
  progress is logged every `:progress_every` input games. When `:limit` is
  reached the stream halts, closing the upstream source.
  """
  @spec filter_lines(Enumerable.t(), keyword()) :: Enumerable.t()
  def filter_lines(lines, opts) do
    initial = %{
      state: :before_game,
      buffer: [],
      tags: %{},
      read: 0,
      kept: 0,
      skipped: 0,
      malformed: 0,
      min_rating: Keyword.get(opts, :min_rating, 2200),
      skip: Keyword.get(opts, :skip, 0),
      limit: Keyword.get(opts, :limit),
      progress_every: Keyword.get(opts, :progress_every, 0),
      stats: Keyword.get(opts, :stats),
      started: Keyword.get(opts, :started, System.monotonic_time(:millisecond)),
      stopped: false
    }

    lines
    |> Stream.concat([@flush])
    |> Stream.transform(initial, fn element, acc ->
      if acc.stopped do
        {:halt, acc}
      else
        case element do
          @flush -> flush(acc)
          line -> process(normalize_line(line), acc)
        end
      end
    end)
  end

  @doc "Whether a game's header tags pass the filter."
  @spec keep_game?(map(), non_neg_integer()) :: boolean()
  def keep_game?(tags, min_rating) do
    white = parse_rating(tags["WhiteElo"])
    black = parse_rating(tags["BlackElo"])

    white != nil and black != nil and white >= min_rating and black >= min_rating and
      not bullet?(tags)
  end

  # --- stream internals --------------------------------------------------------

  defp process("", %{state: :before_game} = acc), do: {[], acc}

  defp process("", acc), do: {[], %{acc | buffer: ["" | acc.buffer]}}

  defp process(line, acc) do
    if Regex.match?(@header_line_regex, line) do
      case acc.state do
        :before_game ->
          {[], %{acc | state: :headers, buffer: [line], tags: tags_of(line)}}

        :headers ->
          {[], %{acc | buffer: [line | acc.buffer], tags: Map.merge(acc.tags, tags_of(line))}}

        :movetext ->
          {acc, emitted} = finalize(acc)

          if acc.stopped do
            {emitted, acc}
          else
            {emitted, %{acc | state: :headers, buffer: [line], tags: tags_of(line)}}
          end
      end
    else
      case acc.state do
        :before_game ->
          # Stray content before the first header (preamble or BOM remnants).
          {[], %{acc | malformed: acc.malformed + 1}}

        _ ->
          {[], %{acc | state: :movetext, buffer: [line | acc.buffer]}}
      end
    end
  end

  defp flush(%{state: :before_game} = acc), do: {[], %{acc | stopped: true}}

  defp flush(acc) do
    {acc, emitted} = finalize(acc)
    {emitted, %{acc | stopped: true}}
  end

  # Counts the buffered game as read, decides keep/drop, and clears the
  # buffer; stops the stream when the input limit is reached.
  defp finalize(acc) do
    read = acc.read + 1
    game = Enum.reverse(acc.buffer)

    {kept, skipped, emitted} =
      cond do
        read <= acc.skip -> {acc.kept, acc.skipped + 1, []}
        keep_game?(acc.tags, acc.min_rating) -> {acc.kept + 1, acc.skipped, game}
        true -> {acc.kept, acc.skipped, []}
      end

    acc = %{
      acc
      | state: :before_game,
        buffer: [],
        tags: %{},
        read: read,
        kept: kept,
        skipped: skipped,
        stopped: acc.limit != nil and read >= acc.limit
    }

    sync_stats(acc)
    log_progress(acc)
    {acc, emitted}
  end

  defp sync_stats(%{stats: nil}), do: :ok

  defp sync_stats(%{stats: stats} = acc) do
    counts = Map.take(acc, [:read, :kept, :skipped, :malformed])
    Agent.update(stats, fn current -> Map.merge(current, counts) end)
  end

  defp log_progress(%{progress_every: every, read: read} = acc)
       when is_integer(every) and every > 0 and rem(read, every) == 0 do
    elapsed_s = max(System.monotonic_time(:millisecond) - acc.started, 1) / 1000
    handed = if acc.stats, do: Agent.get(acc.stats, & &1.handed), else: 0

    Logger.info(
      "bulk import progress: read=#{read} kept=#{acc.kept} skipped=#{acc.skipped} " <>
        "handed=#{handed} rate=#{round(read / elapsed_s)} games/s"
    )
  end

  defp log_progress(_acc), do: :ok

  defp normalize_line(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end

  defp bullet?(tags) do
    event = tags["Event"] || ""
    String.contains?(event, "Bullet") or short_time_control?(tags["TimeControl"])
  end

  defp short_time_control?(time_control) when is_binary(time_control) do
    case Regex.run(~r/^(\d+)/, time_control) do
      [_, seconds] -> String.to_integer(seconds) < 180
      _ -> false
    end
  end

  defp short_time_control?(_), do: false

  defp parse_rating(nil), do: nil

  defp parse_rating(value) do
    case Integer.parse(value) do
      {rating, ""} -> rating
      _ -> nil
    end
  end

  defp tags_of(line) do
    case Regex.run(@tag_regex, line) do
      [_, name, value] -> %{name => value}
      _ -> %{}
    end
  end

  # --- sources -----------------------------------------------------------------

  defp prepare_source!(opts) do
    cond do
      path = opts[:path] ->
        %{
          kind: :file,
          name: Path.basename(path),
          lines: File.stream!(path, :line, []),
          finish: fn _ -> :ok end
        }

      url = opts[:url] ->
        prepare_pipeline!(url)

      true ->
        raise ArgumentError, "either :url or :path is required"
    end
  end

  defp prepare_pipeline!(url) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-bulk-#{System.unique_integer([:positive, :monotonic])}"
      )

    fifo = Path.join(dir, "dump.pgn")
    status_path = Path.join(dir, "status")
    File.mkdir_p!(dir)
    {_, 0} = System.cmd("mkfifo", [fifo])

    # --speed-limit/--speed-time abort a stalled transfer instead of hanging
    # the reader forever on a dead connection.
    script = """
    set -o pipefail
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --speed-limit 10000 --speed-time 30 "$1" | zstd -dc > "$2"
    echo $? > "$3"
    """

    port =
      Port.open({:spawn_executable, bash_path()}, [
        :binary,
        :exit_status,
        args: ["-c", script, "-", url, fifo, status_path]
      ])

    %{
      kind: :url,
      name: url,
      lines: File.stream!(fifo, :line, []),
      finish: fn limited? -> finish_pipeline(limited?, port, status_path, dir) end
    }
  end

  defp finish_pipeline(true, port, _status_path, dir) do
    # The limit halted the reader; the writer dies on the closed pipe.
    if port_alive?(port), do: Port.close(port)
    File.rm_rf(dir)
    Logger.info("bulk import: stopped at the input limit; source closed")
    :ok
  end

  defp finish_pipeline(false, port, status_path, dir) do
    status =
      case File.read(status_path) do
        {:ok, content} ->
          case Integer.parse(String.trim(content)) do
            {code, _} -> code
            _ -> :unreadable
          end

        {:error, _} ->
          :missing
      end

    receive do
      {:exit_status, ^port, _} -> :ok
    after
      5_000 -> if port_alive?(port), do: Port.close(port)
    end

    File.rm_rf(dir)
    if status == 0, do: :ok, else: {:source_failed, status}
  end

  defp port_alive?(port) do
    Port.info(port) != nil
  rescue
    ArgumentError -> false
  end

  defp bash_path do
    case System.find_executable("bash") do
      nil -> raise "bash is required for the download pipeline"
      path -> path
    end
  end

  defp default_prefix(%{name: name}) do
    name
    |> Path.basename()
    |> String.replace_suffix(".zst", "")
    |> String.replace_suffix(".pgn", "")
  end

  # --- summary -----------------------------------------------------------------

  defp build_summary(counts, result, elapsed_ms, source_status) do
    {imported, failures, error} =
      case result do
        {:ok, %{imported_count: imported, failures: failures}} -> {imported, failures, nil}
        {:error, reason} -> {nil, [], reason}
      end

    rate =
      if counts.read > 0 and elapsed_ms > 0 do
        counts.read * 1000 / elapsed_ms
      end

    %{
      read: counts.read,
      kept: counts.kept,
      skipped: counts.skipped,
      malformed_lines: counts.malformed,
      handed: Map.get(counts, :handed, 0),
      imported: imported,
      failure_count: length(failures),
      import_failures: Enum.take(failures, 20),
      error: error,
      elapsed_ms: elapsed_ms,
      rate_per_second: rate,
      source: source_status
    }
  end
end
