# PostgreSQL multi-game position batching experiment.
#
# Compare today's public single-game persistence API against groups of 1, 5,
# 10 and 20 already-parsed games. The grouped path is deliberately LOCAL TO
# THIS BENCHMARK; it reuses existing durable stores without changing them.
#
# WARNING: destructive. Only run against a disposable openchesslab_bench DB.
# Run from the umbrella repository root:
#   $env:DATABASE_URL = "ecto://.../openchesslab_bench"
#   mix run apps/analysis/benchmarks/pgn_multi_game_position_batch.exs
#
# A group is one transaction, whereas production persists one game per
# transaction. That semantics change is NOT production-ready; this measures
# whether the cross-game position batching idea warrants further design.

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

Logger.configure(level: :warning)

defmodule Analysis.PgnMultiGamePositionBatchBenchmark do
  @moduledoc false

  alias Analysis.GameContent
  alias Analysis.GameContentCodec
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PgnBatchImporter
  alias Analysis.PgnImporter
  alias Analysis.PgnLongGameFixture
  alias Analysis.PositionStore
  alias Chess.PositionCodec
  alias OpenChessLab.Repo

  @count_sql """
  SELECT
    (SELECT count(*) FROM positions),
    (SELECT count(*) FROM position_features),
    (SELECT count(*) FROM games),
    (SELECT count(*) FROM game_occurrences),
    (SELECT count(*) FROM game_records)
  """

  @records_sql """
  SELECT
    gr.record_id,
    gr.fullmove_number,
    gr.metadata,
    g.content,
    min(go.position_id) FILTER (WHERE go.ply = 0) AS initial_position_id,
    array_agg(go.ply ORDER BY go.ply) AS plies,
    array_agg(p.record ORDER BY go.ply) AS position_records
  FROM game_records AS gr
  JOIN games AS g ON g.id = gr.game_id
  JOIN game_occurrences AS go ON go.game_id = g.id
  JOIN positions AS p ON p.id = go.position_id
  GROUP BY gr.id, g.id
  ORDER BY gr.record_id
  """

  def run(games, plies, runs, duplicate_percent) do
    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-multi-game-position-batch-#{System.unique_integer([:positive])}.pgn"
      )

    try do
      bytes = PgnLongGameFixture.build_fixture(path, games, plies, duplicate_percent)
      pgn = File.read!(path)

      IO.puts("""
      Multi-game PostgreSQL position batch experiment

      games:         #{games}
      plies/game:    #{plies}
      runs:          #{runs}
      duplicates:    #{duplicate_percent}%
      fixture bytes: #{bytes}
      modes:         reference, 1, 5, 10, 20 games/batch
      """)

      {:ok, parsed_games} = PgnBatchImporter.parse(pgn)

      if length(parsed_games) != games do
        raise "Expected #{games} parsed games, got #{length(parsed_games)}"
      end

      validate_parsed_games!(parsed_games)
      indexed_games = Enum.with_index(parsed_games, 1)
      expected = Map.new(indexed_games, fn {parsed, index} -> {record_id(index), parsed} end)
      modes = [:reference, 1, 5, 10, 20]

      {measurements, reference_signature, reference_counts} =
        Enum.reduce(1..runs, {%{}, nil, nil}, fn run_number, acc ->
          # Rotate execution order to reduce warm-cache/order bias.
          order =
            Enum.drop(modes, rem(run_number - 1, length(modes))) ++
              Enum.take(modes, rem(run_number - 1, length(modes)))

          IO.puts("Run #{run_number} (#{Enum.join(Enum.map(order, &mode_label/1), ", ")}):")

          Enum.reduce(order, acc, fn mode, {results, signature, counts} ->
            cleanup!()
            :erlang.garbage_collect()

            {time_us, queries} = measure(fn -> persist!(indexed_games, mode) end)

            {new_signature, new_counts} =
              validate_durable!(expected, games, plies, duplicate_percent)

            if signature != nil and signature != new_signature do
              raise "Durable contents differ for #{mode_label(mode)} in run #{run_number}"
            end

            if counts != nil and counts != new_counts do
              raise "Durable row counts differ for #{mode_label(mode)} in run #{run_number}: " <>
                      "#{inspect(new_counts)} != #{inspect(counts)}"
            end

            seconds = time_us / 1_000_000

            IO.puts(
              "  #{String.pad_trailing(mode_label(mode), 12)} " <>
                "#{Float.round(seconds, 3)} s | " <>
                "#{Float.round(games / seconds, 1)} games/s | " <>
                "#{queries} queries (#{Float.round(queries / games, 2)}/game)"
            )

            new_results =
              Map.update(results, mode, [{seconds, queries}], &[{seconds, queries} | &1])

            {new_results, signature || new_signature, counts || new_counts}
          end)
        end)

      IO.puts("\nValidated row counts [positions, features, games, occurrences, records]:")
      IO.inspect(reference_counts)
      IO.puts("Durable content SHA256: #{Base.encode16(reference_signature)}")
      IO.puts("\nSummary (medians):")

      reference_median = median(Enum.map(Map.fetch!(measurements, :reference), &elem(&1, 0)))

      Enum.each(modes, fn mode ->
        measurements_for_mode = Map.fetch!(measurements, mode)
        seconds = median(Enum.map(measurements_for_mode, &elem(&1, 0)))
        queries = median(Enum.map(measurements_for_mode, &elem(&1, 1)))

        IO.puts(
          "  #{String.pad_trailing(mode_label(mode), 12)} " <>
            "#{Float.round(seconds, 3)} s | " <>
            "#{Float.round(games / seconds, 1)} games/s | " <>
            "#{Float.round(reference_median / seconds, 2)}x vs reference | " <>
            "#{queries} queries"
        )
      end)

      IO.puts(
        "\nPASS: All modes persisted the same games, metadata, moves and ordered positions."
      )
    after
      cleanup!()
      File.rm(path)
    end
  end

  def handle_query(_event, _measurements, _metadata, table) do
    :ets.update_counter(table, :queries, {2, 1}, {:queries, 0})
    :ok
  end

  defp persist!(indexed_games, :reference) do
    Enum.each(indexed_games, fn {parsed, index} ->
      case PgnImporter.import_parsed(record_id(index), parsed) do
        {:ok, _record} -> :ok
        {:error, reason} -> raise "Reference import failed at #{index}: #{inspect(reason)}"
      end
    end)
  end

  defp persist!(indexed_games, batch_size) when is_integer(batch_size) and batch_size > 0 do
    indexed_games
    |> Enum.chunk_every(batch_size)
    |> Enum.each(&persist_group!/1)
  end

  defp persist_group!(group) do
    case Repo.transaction(fn ->
           positions =
             Enum.flat_map(group, fn {parsed, _index} ->
               [parsed.initial_position | Enum.map(parsed.replay, &elem(&1, 1))]
             end)

           case PositionStore.append_many(positions) do
             {:ok, ids} -> persist_group_records!(group, ids)
             {:error, reason} -> Repo.rollback({:position_store, reason})
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> raise "Grouped import failed: #{inspect(reason)}"
    end
  end

  defp persist_group_records!(group, position_ids) do
    remaining =
      Enum.reduce(group, position_ids, fn {parsed, index}, remaining_ids ->
        expected_count = length(parsed.moves) + 1
        {ids, tail} = Enum.split(remaining_ids, expected_count)

        if length(ids) != expected_count do
          Repo.rollback({:wrong_position_id_count, index, length(ids), expected_count})
        end

        [initial_id | _] = ids
        content = GameContent.new(initial_id, parsed.moves)

        fingerprint =
          case GameFingerprint.for_content(content) do
            {:ok, value} -> value
            {:error, reason} -> Repo.rollback({:fingerprint, index, reason})
          end

        game_id =
          case GameStore.put(fingerprint, content, ids) do
            {:ok, value} -> value
            {:error, reason} -> Repo.rollback({:game_store, index, reason})
          end

        record = GameRecord.new(record_id(index), game_id, parsed.start, metadata(parsed.headers))

        case GameRecordStore.insert(record) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback({:game_record_store, index, reason})
        end

        tail
      end)

    if remaining != [] do
      Repo.rollback({:unconsumed_position_ids, length(remaining)})
    end

    :ok
  end

  defp validate_parsed_games!(parsed_games) do
    Enum.each(parsed_games, fn parsed ->
      replay_matches? =
        Enum.all?(Enum.zip(parsed.moves, parsed.replay), fn {move, {replayed_move, _position}} ->
          move == replayed_move
        end)

      if !(length(parsed.moves) == length(parsed.replay) and replay_matches?) do
        raise "Fixture contains a mismatched replay"
      end

      if !GameRecord.valid_metadata?(metadata(parsed.headers)) do
        raise "Fixture contains invalid record metadata"
      end
    end)
  end

  defp validate_durable!(expected, games, plies, duplicate_percent) do
    [[position_count, feature_count, game_count, occurrence_count, record_count]] =
      Repo.query!(@count_sql, []).rows

    unique_games = games - div(games * duplicate_percent, 100)

    if !(game_count == unique_games and record_count == games and
           occurrence_count == unique_games * (plies + 1) and
           position_count == feature_count) do
      raise "Incorrect durable counts: " <>
              inspect({position_count, feature_count, game_count, occurrence_count, record_count})
    end

    rows = Repo.query!(@records_sql, []).rows

    if length(rows) != games do
      raise "Expected #{games} durable record rows, got #{length(rows)}"
    end

    normalized =
      Enum.map(rows, fn [
                          id,
                          fullmove,
                          stored_metadata,
                          encoded_content,
                          initial_id,
                          stored_plies,
                          stored_positions
                        ] ->
        parsed = Map.fetch!(expected, id)
        {:ok, content} = GameContentCodec.decode(encoded_content)

        expected_positions =
          [parsed.initial_position | Enum.map(parsed.replay, &elem(&1, 1))]
          |> Enum.map(&PositionCodec.encode/1)

        if fullmove != GameStart.fullmove_number(parsed.start) or
             stored_metadata != metadata(parsed.headers) or
             content.moves != parsed.moves or
             content.initial_position_id != initial_id or
             stored_plies != Enum.to_list(0..plies) or
             stored_positions != expected_positions do
          raise "Durable content mismatch for record #{id}"
        end

        {id, fullmove, stored_metadata, content.moves, stored_positions}
      end)

    signature = :crypto.hash(:sha256, :erlang.term_to_binary(normalized))
    {signature, [position_count, feature_count, game_count, occurrence_count, record_count]}
  end

  defp metadata(headers) do
    Map.new(headers, fn {key, value} -> {Macro.underscore(key), value} end)
  end

  defp record_id(index), do: "pgn-multi-position-batch-#{index}"

  defp measure(fun) do
    table = :ets.new(__MODULE__, [:set, :public])
    event = Repo.config() |> Keyword.fetch!(:telemetry_prefix) |> Kernel.++([:query])
    handler_id = {__MODULE__, self(), make_ref()}
    :ok = :telemetry.attach(handler_id, event, &__MODULE__.handle_query/4, table)

    try do
      {elapsed_us, :ok} = :timer.tc(fun)
      [{:queries, queries}] = :ets.lookup(table, :queries)
      {elapsed_us, queries}
    after
      :telemetry.detach(handler_id)
      :ets.delete(table)
    end
  end

  defp median(values) do
    ordered = Enum.sort(values)
    middle = div(length(ordered), 2)

    if rem(length(ordered), 2) == 1 do
      Enum.at(ordered, middle)
    else
      (Enum.at(ordered, middle - 1) + Enum.at(ordered, middle)) / 2
    end
  end

  defp mode_label(:reference), do: "reference"
  defp mode_label(size), do: "group #{size}"

  defp cleanup! do
    Repo.query!(
      """
      TRUNCATE TABLE
        analyses,
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY CASCADE
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

games = System.get_env("PGN_MULTI_BATCH_GAMES", "200") |> String.to_integer()
plies = System.get_env("PGN_MULTI_BATCH_PLIES", "80") |> String.to_integer()
runs = System.get_env("PGN_MULTI_BATCH_RUNS", "3") |> String.to_integer()

duplicate_percent =
  System.get_env("PGN_MULTI_BATCH_DUPLICATE_PERCENT", "0") |> String.to_integer()

if games <= 0 or plies < 2 or plies > 120 or runs <= 0 or
     duplicate_percent < 0 or duplicate_percent >= 100 do
  raise "Expected games > 0, plies 2..120, runs > 0, duplicates 0..99"
end

Analysis.PgnMultiGamePositionBatchBenchmark.run(games, plies, runs, duplicate_percent)
