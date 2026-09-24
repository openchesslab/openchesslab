defmodule PositionDB.Storage.PostingIndex.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-posting-index-disk-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory,
      index:
        Disk.new(
          directory,
          bucket_count: 1
        )
    }
  end

  test "requires a positive bucket count", %{
    directory: directory
  } do
    assert_raise ArgumentError,
                 "bucket_count must be positive",
                 fn ->
                   Disk.new(
                     directory,
                     bucket_count: 0
                   )
                 end
  end

  test "adds and looks up a posting", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert Disk.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}
  end

  test "returns position ids in ascending order", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               3
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               2
             )

    assert Disk.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1, 2, 3]}
  end

  test "adding the same posting is idempotent", %{
    directory: directory,
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert Disk.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}

    path =
      Layout.bucket_path(
        directory,
        0
      )

    assert File.read!(path) ==
             Entry.encode(
               <<"key-a">>,
               1
             )
  end

  test "keeps different keys separate even inside the same bucket", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-b">>,
               2
             )

    assert Disk.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}

    assert Disk.lookup(
             index,
             <<"key-b">>
           ) ==
             {:ok, [2]}
  end

  test "returns zero cardinality for an unknown key", %{
    index: index
  } do
    assert Disk.cardinality(
             index,
             <<"missing">>
           ) ==
             {:ok, 0}

    assert Disk.lookup(
             index,
             <<"missing">>
           ) ==
             {:ok, []}
  end

  test "returns the posting cardinality", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"key-a">>,
               2
             )

    assert Disk.cardinality(
             index,
             <<"key-a">>
           ) ==
             {:ok, 2}
  end

  test "can reopen postings from the same directory", %{
    directory: directory,
    index: index
  } do
    assert {:ok, _index} =
             Disk.add(
               index,
               <<"key-a">>,
               42
             )

    reopened =
      Disk.new(
        directory,
        bucket_count: 1
      )

    assert Disk.lookup(
             reopened,
             <<"key-a">>
           ) ==
             {:ok, [42]}
  end

  test "recovers an interrupted posting append", %{
    directory: directory,
    index: index
  } do
    pending =
      Entry.encode(
        <<"key-a">>,
        10
      )

    path =
      Layout.bucket_path(
        directory,
        0
      )

    File.write!(
      path,
      binary_part(
        pending,
        0,
        5
      )
    )

    assert :ok =
             Disk.recover_pending_append(
               index,
               <<"key-a">>,
               10
             )

    assert Disk.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [10]}
  end
end
