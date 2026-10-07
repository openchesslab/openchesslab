defmodule Analysis.PgnBatchImporterParallelTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.PgnBatchImporter
  alias Analysis.PgnBatchImporter.ParallelImportResult
  alias Analysis.PgnImporter

  test "imports games concurrently and reports the successful count" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    record_ids = %{
      1 => first_id,
      2 => second_id
    }

    lines =
      lines("""
      [Event "First"]

      1. e4 e5 *

      [Event "Second"]

      1. d4 d5 *
      """)

    assert {:ok,
            %ParallelImportResult{
              imported_count: 2,
              failures: []
            }} =
             PgnBatchImporter.import_stream_parallel(
               lines,
               &Map.fetch!(
                 record_ids,
                 &1
               ),
               2
             )

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert {:ok, second} =
             GameRecords.get(second_id)

    assert GameRecord.metadata(first)["event"] ==
             "First"

    assert GameRecord.metadata(second)["event"] ==
             "Second"
  end

  test "continues after an invalid game and reports its source index" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    third_id =
      unique_record_id()

    record_ids = %{
      1 => first_id,
      2 => second_id,
      3 => third_id
    }

    source =
      lines("""
      [Event "First"]

      1. e4 *

      [Event "Broken"]

      1. d4 ThisIsNotSAN *

      [Event "Third"]

      1. c4 *
      """)

    assert {:ok,
            %ParallelImportResult{
              imported_count: 2,
              failures: [
                {
                  :invalid_game,
                  2,
                  {
                    :invalid_pgn,
                    message
                  }
                }
              ]
            }} =
             PgnBatchImporter.import_stream_parallel(
               source,
               &Map.fetch!(
                 record_ids,
                 &1
               ),
               2
             )

    assert message =~
             "Could not parse move"

    assert {:ok, _first} =
             GameRecords.get(first_id)

    assert GameRecords.get(second_id) ==
             :not_found

    assert {:ok, _third} =
             GameRecords.get(third_id)
  end

  test "continues after a persistence failure" do
    first_id =
      unique_record_id()

    existing_id =
      unique_record_id()

    third_id =
      unique_record_id()

    assert {:ok, existing} =
             PgnImporter.import_game(
               existing_id,
               """
               [Event "Existing"]

               1. c4 *
               """
             )

    record_ids = %{
      1 => first_id,
      2 => existing_id,
      3 => third_id
    }

    source =
      lines("""
      [Event "First"]

      1. e4 *

      [Event "Second"]

      1. d4 *

      [Event "Third"]

      1. Nf3 *
      """)

    assert PgnBatchImporter.import_stream_parallel(
             source,
             &Map.fetch!(
               record_ids,
               &1
             ),
             2
           ) ==
             {:ok,
              %ParallelImportResult{
                imported_count: 2,
                failures: [
                  {
                    :import_failed,
                    2,
                    :already_exists
                  }
                ]
              }}

    assert {:ok, _first} =
             GameRecords.get(first_id)

    assert GameRecords.get(existing_id) ==
             {:ok, existing}

    assert {:ok, _third} =
             GameRecords.get(third_id)
  end

  test "reports invalid caller supplied record IDs without stopping later games" do
    first_id =
      unique_record_id()

    third_id =
      unique_record_id()

    source =
      lines("""
      [Event "First"]

      1. e4 *

      [Event "Second"]

      1. d4 *

      [Event "Third"]

      1. c4 *
      """)

    assert PgnBatchImporter.import_stream_parallel(
             source,
             fn
               1 ->
                 first_id

               2 ->
                 ""

               3 ->
                 third_id
             end,
             2
           ) ==
             {:ok,
              %ParallelImportResult{
                imported_count: 2,
                failures: [
                  {
                    :invalid_record_id,
                    2
                  }
                ]
              }}

    assert {:ok, _first} =
             GameRecords.get(first_id)

    assert {:ok, _third} =
             GameRecords.get(third_id)
  end

  test "rejects invalid concurrency before consuming the stream" do
    test_pid =
      self()

    source =
      [
        "[Event \"First\"]",
        "",
        "1. e4 *"
      ]
      |> Stream.map(fn line ->
        send(
          test_pid,
          :line_consumed
        )

        line
      end)

    assert PgnBatchImporter.import_stream_parallel(
             source,
             fn index ->
               "parallel-#{index}"
             end,
             0
           ) ==
             {:error,
              {
                :invalid_max_concurrency,
                0
              }}

    refute_received :line_consumed
  end

  test "imports a PGN file through the bounded parallel boundary" do
    first_id =
      unique_record_id()

    second_id =
      unique_record_id()

    path =
      temporary_pgn_path()

    File.write!(
      path,
      """
      [Event "First from file"]

      1. e4 e5 *

      [Event "Second from file"]

      1. d4 d5 *
      """
    )

    on_exit(fn ->
      File.rm(path)
    end)

    record_ids = %{
      1 => first_id,
      2 => second_id
    }

    assert PgnBatchImporter.import_file_parallel(
             path,
             &Map.fetch!(
               record_ids,
               &1
             ),
             2
           ) ==
             {:ok,
              %ParallelImportResult{
                imported_count: 2,
                failures: []
              }}

    assert {:ok, first} =
             GameRecords.get(first_id)

    assert {:ok, second} =
             GameRecords.get(second_id)

    assert GameRecord.metadata(first)["event"] ==
             "First from file"

    assert GameRecord.metadata(second)["event"] ==
             "Second from file"
  end

  test "parallel file import reports file open errors" do
    missing_path =
      temporary_pgn_path()

    assert PgnBatchImporter.import_file_parallel(
             missing_path,
             fn index ->
               "missing-parallel-file-#{index}"
             end,
             8
           ) ==
             {:error,
              {
                :file,
                :enoent
              }}
  end

  defp lines(pgn) do
    pgn
    |> String.split(
      ~r/\R/,
      trim: false
    )
    |> Stream.map(& &1)
  end

  defp unique_record_id do
    "pgn-parallel-import-test-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end

  defp temporary_pgn_path do
    Path.join(
      System.tmp_dir!(),
      "openchesslab-pgn-parallel-#{System.unique_integer([:positive])}.pgn"
    )
  end
end
