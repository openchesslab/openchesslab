# Destructive benchmark. Requires an explicitly selected openchesslab_bench DB.
# Compares the original single-record transaction path (size 1) against
# production group size 10 on the same file-backed, bounded streaming path.
# Example:
# $env:DATABASE_URL = 'ecto://openchesslab:openchesslab@localhost/openchesslab_bench'
# $env:PGN_GROUP_BENCH_GAMES = '200'
# $env:PGN_GROUP_BENCH_PLIES = '80'
# mix run apps/analysis/benchmarks/pgn_stream_grouped.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))
Logger.configure(level: :warning)

defmodule Analysis.PgnStreamGroupedBenchmark do
  @moduledoc false

  alias Analysis.GameContentCodec
  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias OpenChessLab.Repo

  @rows_sql """
  SELECT gr.record_id, gr.fullmove_number, gr.metadata, g.content,
         array_agg(go.ply ORDER BY go.ply),
         array_agg(p.record ORDER BY go.ply)
  FROM game_records gr
  JOIN games g ON g.id = gr.game_id
  JOIN game_occurrences go ON go.game_id = g.id
  JOIN positions p ON p.id = go.position_id
  GROUP BY gr.id, g.id
  ORDER BY gr.record_id
  """

  def run(game_count, plies, runs, duplicate_percent) do
    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-stream-groups-#{System.unique_integer([:positive])}.pgn"
      )

    try do
      bytes = PgnLongGameFixture.build_fixture(path, game_count, plies, duplicate_percent)

      IO.puts(
        "Fixture: #{game_count} games, #{plies} plies/game, #{duplicate_percent}% duplicates, #{bytes} bytes"
      )

      IO.puts("Modes: original single-game vs grouped 10; #{runs} alternating runs")
      expected_signature = nil

      {_signature, measurements} =
        Enum.reduce(1..runs, {expected_signature, %{1 => [], 10 => []}}, fn run,
                                                                            {signature,
                                                                             measurements} ->
          order = if rem(run, 2) == 1, do: [1, 10], else: [10, 1]

          Enum.reduce(order, {signature, measurements}, fn size, {reference, results} ->
            cleanup!()
            :erlang.garbage_collect()

            measured =
              measure(fn ->
                path
                |> File.stream!(:line, [])
                |> PgnBatchImporter.import_stream(fn index -> "group-bench-#{index}" end, size)
                |> case do
                  {:ok, ^game_count} -> :ok
                  other -> raise "Import failed: #{inspect(other)}"
                end
              end)

            current = signature_and_verify!(game_count, plies, duplicate_percent)

            if reference != nil and current != reference do
              raise "Durable contents differ in group size #{size}, run #{run}"
            end

            seconds = measured.microseconds / 1_000_000

            IO.puts(
              "Run #{run} size #{size}: #{Float.round(seconds, 3)} s | " <>
                "#{Float.round(game_count / seconds, 1)} games/s | " <>
                "#{measured.queries} queries | peak BEAM growth #{Float.round(measured.peak_growth / 1_048_576, 2)} MiB"
            )

            {reference || current, Map.update!(results, size, &[measured | &1])}
          end)
        end)

      IO.puts("\nMedian results:")

      for size <- [1, 10] do
        values = Map.fetch!(measurements, size)
        seconds = median(Enum.map(values, fn value -> value.microseconds / 1_000_000 end))
        queries = median(Enum.map(values, & &1.queries))
        memory = median(Enum.map(values, & &1.peak_growth))

        IO.puts(
          "  size #{size}: #{Float.round(seconds, 3)} s | " <>
            "#{Float.round(game_count / seconds, 1)} games/s | " <>
            "#{Float.round(queries / game_count, 2)} queries/game | " <>
            "#{Float.round(memory / 1_048_576, 2)} MiB peak growth"
        )
      end

      IO.puts("PASS: exact ordered moves, metadata, and position records agree across both modes")
    after
      cleanup!()
      File.rm(path)
    end
  end

  def handle_query(_event, _measurements, _metadata, table) do
    :ets.update_counter(table, :queries, {2, 1}, {:queries, 0})
    :ok
  end

  defp measure(fun) do
    table = :ets.new(__MODULE__, [:set, :public])
    event = Repo.config() |> Keyword.fetch!(:telemetry_prefix) |> Kernel.++([:query])
    handler_id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler_id, event, &__MODULE__.handle_query/4, table)

    baseline = :erlang.memory(:total)
    parent = self()
    ref = make_ref()
    sampler = spawn(fn -> sample_memory(parent, ref, baseline) end)

    try do
      {microseconds, :ok} = :timer.tc(fun)
      send(sampler, {:stop, ref})

      peak =
        receive do
          {:peak, ^ref, n} -> n
        after
          5_000 -> raise "Memory sampler did not stop"
        end

      queries = :ets.lookup_element(table, :queries, 2)
      %{microseconds: microseconds, queries: queries, peak_growth: max(0, peak - baseline)}
    after
      send(sampler, {:stop, ref})
      :telemetry.detach(handler_id)
      :ets.delete(table)
    end
  end

  defp sample_memory(parent, ref, peak) do
    receive do
      {:stop, ^ref} -> send(parent, {:peak, ref, max(peak, :erlang.memory(:total))})
    after
      5 -> sample_memory(parent, ref, max(peak, :erlang.memory(:total)))
    end
  end

  defp signature_and_verify!(games, plies, duplicates) do
    [[positions, features, canonicals, occurrences, records]] =
      Repo.query!(
        """
        SELECT (SELECT count(*) FROM positions),
               (SELECT count(*) FROM position_features),
               (SELECT count(*) FROM games),
               (SELECT count(*) FROM game_occurrences),
               (SELECT count(*) FROM game_records)
        """,
        []
      ).rows

    unique = games - div(games * duplicates, 100)

    if positions != features or canonicals != unique or records != games or
         occurrences != unique * (plies + 1) do
      raise "Incorrect durable counts: #{inspect({positions, features, canonicals, occurrences, records})}"
    end

    rows = Repo.query!(@rows_sql, []).rows
    if length(rows) != games, do: raise("Missing durable game records")

    canonical =
      Enum.map(rows, fn [id, fullmove, metadata, encoded, stored_plies, pos_records] ->
        {:ok, content} = GameContentCodec.decode(encoded)
        if stored_plies != Enum.to_list(0..plies), do: raise("Incorrect plies for #{id}")
        {id, fullmove, metadata, content.moves, pos_records}
      end)

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical))
  end

  defp median(values) do
    values = Enum.sort(values)
    middle = div(length(values), 2)

    if rem(length(values), 2) == 1,
      do: Enum.at(values, middle),
      else: (Enum.at(values, middle - 1) + Enum.at(values, middle)) / 2
  end

  defp cleanup! do
    Repo.query!(
      """
      TRUNCATE TABLE analyses, game_records, game_occurrences, games,
                     position_features, positions RESTART IDENTITY CASCADE
      """,
      []
    )

    :ok
  end
end

url = System.get_env("DATABASE_URL") || raise "DATABASE_URL must be explicitly set"

if URI.parse(url).path != "/openchesslab_bench" do
  raise "Refusing destructive benchmark: DATABASE_URL must target openchesslab_bench"
end

games = System.get_env("PGN_GROUP_BENCH_GAMES", "200") |> String.to_integer()
plies = System.get_env("PGN_GROUP_BENCH_PLIES", "80") |> String.to_integer()
runs = System.get_env("PGN_GROUP_BENCH_RUNS", "3") |> String.to_integer()
duplicates = System.get_env("PGN_GROUP_BENCH_DUPLICATE_PERCENT", "0") |> String.to_integer()

if games <= 0 or plies < 2 or plies > 120 or runs <= 0 or
     duplicates < 0 or duplicates >= 100 do
  raise "Expected games > 0, plies 2..120, runs > 0, duplicates 0..99"
end

Analysis.PgnStreamGroupedBenchmark.run(games, plies, runs, duplicates)
