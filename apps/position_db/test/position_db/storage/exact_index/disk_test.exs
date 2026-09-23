defmodule PositionDB.Storage.ExactIndex.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Disk
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  defmodule TestHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id do
      <<"test-exact-hash-v1">>
    end

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size do
      4
    end

    @impl PositionDB.Storage.ExactKeyHash
    def hash(<<"a">>),
      do: {:ok, <<0, 0, 0, 1>>}

    def hash(<<"b">>),
      do: {:ok, <<0, 0, 0, 2>>}

    def hash(<<"collision-a">>),
      do: {:ok, <<0, 0, 0, 3>>}

    def hash(<<"collision-b">>),
      do: {:ok, <<0, 0, 0, 3>>}

    def hash(_key),
      do: {:ok, <<0, 0, 0, 15>>}
  end

  defmodule FailingHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id, do: <<"failing-v1">>

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size, do: 4

    @impl PositionDB.Storage.ExactKeyHash
    def hash(_key),
      do: {:error, :cannot_hash}
  end

  defmodule WrongSizeHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id, do: <<"wrong-size-v1">>

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size, do: 4

    @impl PositionDB.Storage.ExactKeyHash
    def hash(_key),
      do: {:ok, <<1, 2, 3>>}
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-index-disk-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    opts = [
      bucket_count: 16,
      hash: TestHash
    ]

    index =
      Disk.new(
        directory,
        opts
      )

    %{
      directory: directory,
      index: index,
      opts: opts
    }
  end

  test "returns no candidates for an unknown key", %{
    index: index
  } do
    assert Disk.lookup(
             index,
             <<"missing">>
           ) ==
             {:ok, []}
  end

  test "adds and finds a candidate", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "survives reopening the index", %{
    directory: directory,
    index: index,
    opts: opts
  } do
    assert {:ok, _index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    reopened =
      Disk.new(
        directory,
        opts
      )

    assert Disk.lookup(
             reopened,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "does not add the same candidate twice", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "keeps different hashes separate", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"b">>,
               20
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}

    assert Disk.lookup(
             index,
             <<"b">>
           ) ==
             {:ok, [20]}
  end

  test "returns all candidates when different keys have the same hash", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"collision-a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"collision-b">>,
               20
             )

    assert Disk.lookup(
             index,
             <<"collision-a">>
           ) ==
             {:ok, [10, 20]}

    assert Disk.lookup(
             index,
             <<"collision-b">>
           ) ==
             {:ok, [10, 20]}
  end

  test "propagates bucket corruption", %{
    directory: directory,
    index: index
  } do
    assert {:ok, hash} =
             TestHash.hash(<<"a">>)

    bucket =
      Layout.bucket(
        hash,
        16
      )

    path =
      Layout.bucket_path(
        directory,
        bucket
      )

    File.write!(
      path,
      <<1, 2, 3>>
    )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:error, :partial_entry}
  end

  test "propagates hash implementation errors", %{
    directory: directory
  } do
    index =
      Disk.new(
        directory,
        bucket_count: 16,
        hash: FailingHash
      )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:error, :cannot_hash}
  end

  test "rejects hashes whose size differs from the declared size", %{
    directory: directory
  } do
    index =
      Disk.new(
        directory,
        bucket_count: 16,
        hash: WrongSizeHash
      )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:error, {:invalid_hash_size, 4, 3}}
  end
end
