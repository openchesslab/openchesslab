defmodule GameDB.Storage.Disk.PositionOccurrenceIndexTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.PositionOccurrenceIndex

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-position-occurrence-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    index =
      PositionOccurrenceIndex.new(
        directory,
        bucket_count: 4
      )

    %{
      directory: directory,
      index: index
    }
  end

  test "requires a positive bucket count", %{
    directory: directory
  } do
    assert_raise ArgumentError,
                 "bucket_count must be positive",
                 fn ->
                   PositionOccurrenceIndex.new(
                     directory,
                     bucket_count: 0
                   )
                 end
  end

  test "scans occurrence ids incrementally", %{
    index: index
  } do
    assert {:ok, index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {10, 1},
                 {20, 2},
                 {10, 3}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert {:ok, 1, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert {:ok, 3, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "keeps different positions in the same bucket separate", %{
    index: index
  } do
    assert {:ok, index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {1, 10},
                 {5, 20}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        1
      )

    assert {:ok, 10, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)

    scan =
      PositionOccurrenceIndex.scan(
        index,
        5
      )

    assert {:ok, 20, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "finishes a scan for an unknown position", %{
    index: index
  } do
    scan =
      PositionOccurrenceIndex.scan(
        index,
        999
      )

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "can reopen postings from the same directory", %{
    directory: directory,
    index: index
  } do
    assert {:ok, _index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {10, 42}
               ]
             )

    reopened =
      PositionOccurrenceIndex.new(
        directory,
        bucket_count: 4
      )

    scan =
      PositionOccurrenceIndex.scan(
        reopened,
        10
      )

    assert {:ok, 42, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "detects a partial bucket entry", %{
    directory: directory,
    index: index
  } do
    path =
      bucket_path(
        directory,
        2
      )

    File.write!(
      path,
      <<1, 2, 3>>
    )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert PositionOccurrenceIndex.scan_next(scan) ==
             {:error, :partial_entry}
  end

  test "recovers missing postings", %{
    index: index
  } do
    assert :ok =
             PositionOccurrenceIndex.recover_pending_appends(
               index,
               [
                 {10, 1},
                 {10, 3},
                 {20, 2}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert {:ok, 1, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert {:ok, 3, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "recovery preserves complete postings and appends missing ones", %{
    index: index
  } do
    assert {:ok, index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {10, 1}
               ]
             )

    assert :ok =
             PositionOccurrenceIndex.recover_pending_appends(
               index,
               [
                 {10, 1},
                 {10, 2}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert {:ok, 1, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert {:ok, 2, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "recovers a matching partial posting", %{
    directory: directory,
    index: index
  } do
    assert {:ok, index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {10, 1}
               ]
             )

    entry =
      <<
        10::unsigned-big-64,
        2::unsigned-big-64
      >>

    path =
      bucket_path(
        directory,
        2
      )

    File.write!(
      path,
      binary_part(
        entry,
        0,
        9
      ),
      [:append]
    )

    assert :ok =
             PositionOccurrenceIndex.recover_pending_appends(
               index,
               [
                 {10, 1},
                 {10, 2}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert {:ok, 1, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert {:ok, 2, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  test "refuses an unrelated partial posting", %{
    directory: directory,
    index: index
  } do
    path =
      bucket_path(
        directory,
        2
      )

    File.write!(
      path,
      <<255, 255, 255>>
    )

    assert PositionOccurrenceIndex.recover_pending_appends(
             index,
             [
               {10, 1}
             ]
           ) ==
             {:error, :unexpected_partial_entry}

    assert File.read!(path) ==
             <<255, 255, 255>>
  end

  test "deduplicates postings within one batch", %{
    index: index
  } do
    assert {:ok, index} =
             PositionOccurrenceIndex.add_all(
               index,
               [
                 {10, 1},
                 {10, 1}
               ]
             )

    scan =
      PositionOccurrenceIndex.scan(
        index,
        10
      )

    assert {:ok, 1, scan} =
             PositionOccurrenceIndex.scan_next(scan)

    assert :done =
             PositionOccurrenceIndex.scan_next(scan)
  end

  defp bucket_path(
         directory,
         bucket
       ) do
    filename =
      bucket
      |> Integer.to_string()
      |> String.pad_leading(
        8,
        "0"
      )
      |> then(&"bucket-#{&1}.idx")

    Path.join(
      directory,
      filename
    )
  end
end
