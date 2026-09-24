defmodule PositionDB.Storage.Disk.ExactIndexBuilderTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.ExactIndexBuilder
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

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
    def hash(<<"aaaa">>) do
      {:ok, <<0, 0, 0, 1>>}
    end

    def hash(<<"bbbb">>) do
      {:ok, <<0, 0, 0, 1>>}
    end

    def hash(<<"cccc">>) do
      {:ok, <<0, 0, 0, 2>>}
    end

    def hash(_record) do
      {:ok, <<0, 0, 0, 15>>}
    end
  end

  defmodule FailingHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id do
      <<"failing-hash-v1">>
    end

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size do
      4
    end

    @impl PositionDB.Storage.ExactKeyHash
    def hash(_record) do
      {:error, :cannot_hash}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-index-builder-#{System.unique_integer([:positive])}"
      )

    records_directory =
      Path.join(
        root,
        "records"
      )

    exact_index_directory =
      Path.join(
        root,
        "exact-index"
      )

    File.mkdir_p!(records_directory)

    File.mkdir_p!(exact_index_directory)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    record_store =
      RecordStore.new(
        records_directory,
        record_size: 4,
        records_per_segment: 2
      )

    exact_index =
      ExactIndex.new(
        exact_index_directory,
        bucket_count: 16,
        hash: TestHash
      )

    %{
      root: root,
      record_store: record_store,
      exact_index: exact_index
    }
  end

  test "builds an exact index from all position records", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    assert :ok =
             RecordStore.append(
               record_store,
               2,
               <<"bbbb">>
             )

    assert :ok =
             RecordStore.append(
               record_store,
               3,
               <<"cccc">>
             )

    assert {:ok, exact_index} =
             ExactIndexBuilder.build(
               record_store,
               exact_index
             )

    assert ExactIndex.lookup(
             exact_index,
             <<"aaaa">>
           ) ==
             {:ok, [1, 2]}

    assert ExactIndex.lookup(
             exact_index,
             <<"bbbb">>
           ) ==
             {:ok, [1, 2]}

    assert ExactIndex.lookup(
             exact_index,
             <<"cccc">>
           ) ==
             {:ok, [3]}
  end

  test "builds an empty index from an empty record store", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert {:ok, exact_index} =
             ExactIndexBuilder.build(
               record_store,
               exact_index
             )

    assert ExactIndex.lookup(
             exact_index,
             <<"aaaa">>
           ) ==
             {:ok, []}
  end

  test "refuses to build into a non-empty exact index", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    assert {:ok, exact_index} =
             ExactIndex.add(
               exact_index,
               <<"stale">>,
               99
             )

    assert ExactIndexBuilder.build(
             record_store,
             exact_index
           ) ==
             {:error, :exact_index_not_empty}
  end

  test "propagates record store corruption", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    File.write!(
      Path.join(
        record_store.directory,
        "segment-00000000.dat"
      ),
      <<"abc">>
    )

    assert ExactIndexBuilder.build(
             record_store,
             exact_index
           ) ==
             {:error, {:invalid_segment_size, 0, 3}}
  end

  test "propagates exact hash errors", %{
    root: root,
    record_store: record_store
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    directory =
      Path.join(
        root,
        "failing-index"
      )

    File.mkdir!(directory)

    exact_index =
      ExactIndex.new(
        directory,
        bucket_count: 16,
        hash: FailingHash
      )

    assert ExactIndexBuilder.build(
             record_store,
             exact_index
           ) ==
             {:error, :cannot_hash}
  end
end
