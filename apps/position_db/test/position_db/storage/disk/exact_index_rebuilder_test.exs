defmodule PositionDB.Storage.Disk.ExactIndexRebuilderTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.ExactIndexRebuilder
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
      {:ok, <<0, 0, 0, 2>>}
    end

    def hash(_record) do
      {:ok, <<0, 0, 0, 15>>}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-index-rebuilder-#{System.unique_integer([:positive])}"
      )

    records_directory =
      Path.join(
        root,
        "records"
      )

    index_directory =
      Path.join(
        root,
        "exact-index"
      )

    File.mkdir_p!(records_directory)

    File.mkdir_p!(index_directory)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    record_store =
      RecordStore.new(
        records_directory,
        record_size: 4,
        records_per_segment: 3
      )

    exact_index =
      ExactIndex.new(
        index_directory,
        bucket_count: 16,
        hash: TestHash
      )

    %{
      root: root,
      record_store: record_store,
      exact_index: exact_index,
      index_directory: index_directory
    }
  end

  test "replaces the active index with one rebuilt from records", %{
    record_store: record_store,
    exact_index: exact_index,
    index_directory: index_directory
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

    assert {:ok, exact_index} =
             ExactIndex.add(
               exact_index,
               <<"aaaa">>,
               1
             )

    assert {:ok, exact_index} =
             ExactIndex.add(
               exact_index,
               <<"stale">>,
               99
             )

    assert ExactIndex.lookup(
             exact_index,
             <<"aaaa">>
           ) ==
             {:ok, [1]}

    assert ExactIndex.lookup(
             exact_index,
             <<"bbbb">>
           ) ==
             {:ok, []}

    assert ExactIndex.lookup(
             exact_index,
             <<"stale">>
           ) ==
             {:ok, [99]}

    assert {:ok, rebuilt} =
             ExactIndexRebuilder.rebuild(
               record_store,
               exact_index
             )

    assert ExactIndex.lookup(
             rebuilt,
             <<"aaaa">>
           ) ==
             {:ok, [1]}

    assert ExactIndex.lookup(
             rebuilt,
             <<"bbbb">>
           ) ==
             {:ok, [2]}

    assert ExactIndex.lookup(
             rebuilt,
             <<"stale">>
           ) ==
             {:ok, []}

    assert File.dir?(index_directory)

    refute File.exists?(
             index_directory <>
               ".rebuild"
           )

    refute File.exists?(
             index_directory <>
               ".backup"
           )
  end

  test "keeps the active index when rebuilding fails", %{
    record_store: record_store,
    exact_index: exact_index,
    index_directory: index_directory
  } do
    assert {:ok, exact_index} =
             ExactIndex.add(
               exact_index,
               <<"aaaa">>,
               99
             )

    File.write!(
      Path.join(
        record_store.directory,
        "segment-00000000.dat"
      ),
      <<"abc">>
    )

    assert ExactIndexRebuilder.rebuild(
             record_store,
             exact_index
           ) ==
             {:error, {:invalid_segment_size, 0, 3}}

    assert ExactIndex.lookup(
             exact_index,
             <<"aaaa">>
           ) ==
             {:ok, [99]}

    assert File.dir?(index_directory)

    refute File.exists?(
             index_directory <>
               ".rebuild"
           )

    refute File.exists?(
             index_directory <>
               ".backup"
           )
  end

  test "removes an interrupted rebuild while the active index still exists", %{
    index_directory: index_directory
  } do
    rebuild =
      index_directory <>
        ".rebuild"

    File.mkdir!(rebuild)

    File.write!(
      Path.join(
        rebuild,
        "partial"
      ),
      <<"partial">>
    )

    assert :ok =
             ExactIndexRebuilder.recover(index_directory)

    assert File.dir?(index_directory)

    refute File.exists?(rebuild)
  end

  test "removes a stale backup after promotion completed", %{
    index_directory: index_directory
  } do
    backup =
      index_directory <>
        ".backup"

    File.mkdir!(backup)

    File.write!(
      Path.join(
        backup,
        "old"
      ),
      <<"old">>
    )

    assert :ok =
             ExactIndexRebuilder.recover(index_directory)

    assert File.dir?(index_directory)

    refute File.exists?(backup)
  end

  test "completes an interrupted promotion", %{
    index_directory: index_directory
  } do
    rebuild =
      index_directory <>
        ".rebuild"

    backup =
      index_directory <>
        ".backup"

    File.write!(
      Path.join(
        index_directory,
        "old"
      ),
      <<"old">>
    )

    File.mkdir!(rebuild)

    File.write!(
      Path.join(
        rebuild,
        "new"
      ),
      <<"new">>
    )

    File.rename!(
      index_directory,
      backup
    )

    refute File.exists?(index_directory)

    assert File.dir?(rebuild)

    assert File.dir?(backup)

    assert :ok =
             ExactIndexRebuilder.recover(index_directory)

    assert File.read!(
             Path.join(
               index_directory,
               "new"
             )
           ) ==
             <<"new">>

    refute File.exists?(
             Path.join(
               index_directory,
               "old"
             )
           )

    refute File.exists?(rebuild)

    refute File.exists?(backup)
  end

  test "restores the backup when the rebuild is missing after the active index moved", %{
    index_directory: index_directory
  } do
    backup =
      index_directory <>
        ".backup"

    File.write!(
      Path.join(
        index_directory,
        "old"
      ),
      <<"old">>
    )

    File.rename!(
      index_directory,
      backup
    )

    refute File.exists?(index_directory)

    assert File.dir?(backup)

    assert :ok =
             ExactIndexRebuilder.recover(index_directory)

    assert File.read!(
             Path.join(
               index_directory,
               "old"
             )
           ) ==
             <<"old">>

    refute File.exists?(backup)
  end

  test "reports an ambiguous recovery state instead of choosing an index", %{
    index_directory: index_directory
  } do
    rebuild =
      index_directory <>
        ".rebuild"

    backup =
      index_directory <>
        ".backup"

    File.mkdir!(rebuild)
    File.mkdir!(backup)

    assert ExactIndexRebuilder.recover(index_directory) ==
             {:error, :ambiguous_exact_index_recovery}

    assert File.dir?(index_directory)

    assert File.dir?(rebuild)

    assert File.dir?(backup)
  end
end
