defmodule Analysis.PgnBatchImporterGroupedTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecords
  alias Analysis.PgnBatchImporter
  alias Analysis.PgnImporter
  alias OpenChessLab.Repo

  # These tests use shared PostgreSQL storage, not an Ecto sandbox.
  # Canonical game IDs are reused globally; prior tests can leave a game
  # with deliberately damaged occurrences behind. Always start with a
  # self-contained fixture, like GameRecordsBatchTest does.
  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        positions
      RESTART IDENTITY CASCADE
      """,
      []
    )

    :ok
  end

  test "default streaming batches persist 21 records and deduplicate canonical games" do
    prefix = prefix()

    games =
      for index <- 1..21, do: {index, if(rem(index, 2) == 1, do: "1. e4 *", else: "1. d4 *")}

    assert PgnBatchImporter.import_stream(lines(games), &id(prefix, &1)) == {:ok, 21}

    assert [[2, 4, 21]] =
             Repo.query!(
               """
               SELECT
                 (SELECT count(*) FROM games),
                 (SELECT count(*) FROM game_occurrences),
                 (SELECT count(*) FROM game_records)
               """,
               []
             ).rows

    for index <- 1..21 do
      assert {:ok, record, content, occurrences} = GameRecords.load(id(prefix, index))
      assert record.metadata["event"] == "Grouped #{index}"
      assert length(content.moves) == 1
      assert Enum.map(occurrences, & &1.ply) == [0, 1]
    end

    assert {:ok, odd} = GameRecords.get(id(prefix, 1))
    assert {:ok, same} = GameRecords.get(id(prefix, 21))
    assert {:ok, different} = GameRecords.get(id(prefix, 2))
    assert odd.game_id == same.game_id
    refute odd.game_id == different.game_id
  end

  test "parse failure inside the second group persists the valid prefix, not later movetext" do
    prefix = prefix()
    parent = self()

    source =
      lines(
        for(
          index <- 1..14,
          do:
            {index,
             if(index == 12,
               do: "1. BadSAN *",
               else: if(index == 13, do: "1. c4 *", else: "1. e4 *")
             )}
        )
      )
      |> Stream.map(fn line ->
        if line == "1. c4 *", do: send(parent, :later_movetext)
        line
      end)

    assert {:error, {:invalid_game, 12, {:invalid_pgn, _message}}} =
             PgnBatchImporter.import_stream(source, &id(prefix, &1))

    for index <- 1..11, do: assert({:ok, _record} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 12)) == :not_found
    assert GameRecords.get(id(prefix, 13)) == :not_found
    refute_received :later_movetext
  end

  test "invalid PGN at the first group boundary preserves nine games" do
    prefix = prefix()
    games = for index <- 1..12, do: {index, if(index == 10, do: "1. NotSAN *", else: "1. e4 *")}

    assert {:error, {:invalid_game, 10, {:invalid_pgn, _}}} =
             PgnBatchImporter.import_stream(lines(games), &id(prefix, &1))

    for index <- 1..9, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 10)) == :not_found
    assert GameRecords.get(id(prefix, 11)) == :not_found
  end

  test "duplicate record IDs in one group fall back to the original first failure" do
    prefix = prefix()
    provider = fn index -> id(prefix, if(index == 4, do: 2, else: index)) end

    assert PgnBatchImporter.import_stream(lines(simple_games(12)), provider) ==
             {:error, {:import_failed, 4, :already_exists}}

    for index <- 1..3, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 4)) == :not_found
    assert GameRecords.get(id(prefix, 5)) == :not_found
  end

  test "duplicate record ID across groups uses the global index 11" do
    prefix = prefix()
    provider = fn index -> id(prefix, if(index == 11, do: 3, else: index)) end

    assert PgnBatchImporter.import_stream(lines(simple_games(23)), provider) ==
             {:error, {:import_failed, 11, :already_exists}}

    for index <- 1..10, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 11)) == :not_found
    assert GameRecords.get(id(prefix, 12)) == :not_found
  end

  test "existing database record at index 6 preserves first five records" do
    prefix = prefix()
    existing_id = id(prefix, 6)

    assert {:ok, existing} =
             PgnImporter.import_game(existing_id, "[Event \"Existing\"]\n\n1. c4 *")

    assert PgnBatchImporter.import_stream(lines(simple_games(12)), &id(prefix, &1)) ==
             {:error, {:import_failed, 6, :already_exists}}

    for index <- 1..5, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(existing_id) == {:ok, existing}
    assert GameRecords.get(id(prefix, 7)) == :not_found
  end

  test "a PostgreSQL check violation is returned at its global index after fallback" do
    prefix = prefix()
    constraint = "pgn_stream_group_forced_failure"

    # Dedicated negative-path integration check. The table is restored even
    # if an assertion fails; the constraint targets only the synthetic ID.
    Repo.query!(
      "ALTER TABLE game_records ADD CONSTRAINT #{constraint} " <>
        "CHECK (record_id NOT LIKE '%__db_failure_7')",
      []
    )

    on_exit(fn ->
      Repo.query!("ALTER TABLE game_records DROP CONSTRAINT IF EXISTS #{constraint}", [])
    end)

    provider = fn index ->
      if index == 7, do: "#{prefix}__db_failure_7", else: id(prefix, index)
    end

    assert {:error,
            {:import_failed, 7,
             {:game_record_store, %Postgrex.Error{postgres: %{code: :check_violation}}}}} =
             PgnBatchImporter.import_stream(lines(simple_games(12)), provider)

    for index <- 1..6, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 8)) == :not_found
  end

  test "an earlier database failure outranks a later invalid PGN in the same group" do
    prefix = prefix()
    games = for index <- 1..9, do: {index, if(index == 8, do: "1. InvalidSAN *", else: "1. e4 *")}
    provider = fn index -> id(prefix, if(index == 5, do: 2, else: index)) end

    assert PgnBatchImporter.import_stream(lines(games), provider) ==
             {:error, {:import_failed, 5, :already_exists}}

    for index <- 1..4, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 6)) == :not_found
  end

  test "invalid record ID after a full group commits the preceding partial prefix" do
    prefix = prefix()
    provider = fn index -> if(index == 12, do: "", else: id(prefix, index)) end

    assert PgnBatchImporter.import_stream(lines(simple_games(14)), provider) ==
             {:error, {:invalid_record_id, 12}}

    for index <- 1..11, do: assert({:ok, _} = GameRecords.get(id(prefix, index)))
    assert GameRecords.get(id(prefix, 12)) == :not_found
    assert GameRecords.get(id(prefix, 13)) == :not_found
  end

  test "a size of one is the original persistence reference and validates sizes" do
    prefix = prefix()

    assert PgnBatchImporter.import_stream(lines(simple_games(3)), &id(prefix, &1), 1) ==
             {:ok, 3}

    assert PgnBatchImporter.import_stream(lines(simple_games(3)), &id(prefix, &1), 0) ==
             {:error, {:invalid_batch_size, 0}}

    assert PgnBatchImporter.import_stream(lines(simple_games(3)), &id(prefix, &1), 11) ==
             {:error, {:invalid_batch_size, 11}}

    assert PgnBatchImporter.import_stream(lines(simple_games(3)), :invalid, 10) ==
             {:error, :invalid_record_id_provider}
  end

  test "a file with a tail batch returns the correct count" do
    prefix = prefix()

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-group-test-#{System.unique_integer([:positive])}.pgn"
      )

    File.write!(path, pgn(simple_games(11)))
    on_exit(fn -> File.rm(path) end)

    assert PgnBatchImporter.import_file(path, &id(prefix, &1)) == {:ok, 11}
    assert {:ok, _} = GameRecords.get(id(prefix, 11))
  end

  test "skip_malformed counts and skips unparseable games in corpus runs" do
    games =
      for index <- 1..7 do
        {index,
         case index do
           2 -> "*"
           5 -> "1. BadSAN *"
           _ -> "1. e4 *"
         end}
      end

    # Strict default: the run aborts on the first malformed game.
    strict_prefix = prefix()

    assert {:error, {:invalid_game, 2, {:invalid_pgn, _}}} =
             PgnBatchImporter.import_stream(lines(games), &id(strict_prefix, &1))

    assert {:ok, _} = GameRecords.get(id(strict_prefix, 1))
    assert GameRecords.get(id(strict_prefix, 3)) == :not_found

    # Corpus mode: dirt is counted and skipped, the rest imports.
    skip_prefix = prefix()

    assert {:ok, %{imported: 5, malformed: 2}} =
             PgnBatchImporter.import_stream(
               lines(games),
               &id(skip_prefix, &1),
               10,
               skip_malformed: true
             )

    for index <- [1, 3, 4, 6, 7], do: assert({:ok, _} = GameRecords.get(id(skip_prefix, index)))
    assert GameRecords.get(id(skip_prefix, 2)) == :not_found
    assert GameRecords.get(id(skip_prefix, 5)) == :not_found
  end

  test "extra headers mark every record's metadata without touching dedup" do
    prefix = prefix()

    games = [{1, "1. e4 *"}, {2, "1. e4 *"}]

    assert PgnBatchImporter.import_stream(
             lines(games),
             &id(prefix, &1),
             10,
             extra_headers: [{"Source", "lichess-elite"}, {"SourceDetail", "2025-11"}]
           ) == {:ok, 2}

    for index <- [1, 2] do
      assert {:ok, record} = GameRecords.get(id(prefix, index))
      assert record.metadata["source"] == "lichess-elite"
      assert record.metadata["source_detail"] == "2025-11"
    end

    # Identical content still dedups to one canonical game, provenance aside.
    assert {:ok, first} = GameRecords.get(id(prefix, 1))
    assert {:ok, second} = GameRecords.get(id(prefix, 2))
    assert first.game_id == second.game_id
  end

  defp simple_games(count), do: for(index <- 1..count, do: {index, "1. e4 *"})

  defp pgn(games) do
    Enum.map_join(games, "\n\n", fn {index, movetext} ->
      "[Event \"Grouped #{index}\"]\n\n#{movetext}"
    end)
  end

  defp lines(games), do: games |> pgn() |> String.split("\n", trim: false) |> Stream.map(& &1)

  defp prefix do
    "pgn-group-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  defp id(prefix, index), do: "#{prefix}-#{index}"
end
