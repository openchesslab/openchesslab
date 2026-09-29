defmodule GameDB.Storage.Disk.CanonicalStoreTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.AppendMarker
  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameRecordStore

  defmodule TestCodec do
    @moduledoc false
    @behaviour GameDB.RecordCodec

    @impl true
    def encode({:game, value}) when is_integer(value) and value >= 0 do
      {:ok,
       <<
         value::unsigned-big-64
       >>}
    end

    def encode(_record) do
      {:error, :invalid_game}
    end

    @impl true
    def decode(<<value::unsigned-big-64>>) do
      {:ok, {:game, value}}
    end

    def decode(_encoded) do
      {:error, :invalid_game_record}
    end
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-canonical-store-#{System.unique_integer([:positive])}"
      )

    opts = [
      codec: TestCodec,
      bucket_count: 16
    ]

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, store} =
             CanonicalStore.create(
               directory,
               opts
             )

    %{
      directory: directory,
      opts: opts,
      store: store
    }
  end

  test "stores and retrieves a canonical game", %{
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, store, 1} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 42}
             )

    assert CanonicalStore.get(
             store,
             1
           ) ==
             {:ok, {:game, 42}}

    assert CanonicalStore.find(
             store,
             fingerprint,
             {:game, 42}
           ) ==
             {:ok, 1}

    assert CanonicalStore.cardinality(store) ==
             {:ok, 1}
  end

  test "returns the existing id for the same canonical game", %{
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, store, 1} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 42}
             )

    assert {:ok, store, 1} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 42}
             )

    assert CanonicalStore.cardinality(store) ==
             {:ok, 1}
  end

  test "keeps different games with the same fingerprint separate", %{
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, store, 1} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 42}
             )

    assert {:ok, store, 2} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 99}
             )

    assert CanonicalStore.find(
             store,
             fingerprint,
             {:game, 42}
           ) ==
             {:ok, 1}

    assert CanonicalStore.find(
             store,
             fingerprint,
             {:game, 99}
           ) ==
             {:ok, 2}
  end

  test "reopens persisted canonical games", %{
    directory: directory,
    opts: opts,
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, _store, 1} =
             CanonicalStore.put(
               store,
               fingerprint,
               {:game, 42}
             )

    assert {:ok, reopened} =
             CanonicalStore.open(
               directory,
               opts
             )

    assert CanonicalStore.get(
             reopened,
             1
           ) ==
             {:ok, {:game, 42}}

    assert CanonicalStore.find(
             reopened,
             fingerprint,
             {:game, 42}
           ) ==
             {:ok, 1}

    assert CanonicalStore.cardinality(reopened) ==
             {:ok, 1}
  end

  test "scans persisted game ids", %{
    store: store
  } do
    assert {:ok, store, 1} =
             CanonicalStore.put(
               store,
               fingerprint(1),
               {:game, 1}
             )

    assert {:ok, store, 2} =
             CanonicalStore.put(
               store,
               fingerprint(2),
               {:game, 2}
             )

    assert {:ok, scan} =
             CanonicalStore.scan(store)

    assert {:ok, 1, scan} =
             CanonicalStore.scan_next(scan)

    assert {:ok, 2, scan} =
             CanonicalStore.scan_next(scan)

    assert :done =
             CanonicalStore.scan_next(scan)
  end

  test "clears a pending append when no game record was published", %{
    directory: directory,
    opts: opts
  } do
    assert :ok =
             AppendMarker.create(
               directory,
               1
             )

    assert {:ok, reopened} =
             CanonicalStore.open(
               directory,
               opts
             )

    assert CanonicalStore.cardinality(reopened) ==
             {:ok, 0}

    assert AppendMarker.read(directory) ==
             :none
  end

  test "recovers a missing fingerprint index entry", %{
    directory: directory,
    opts: opts,
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert :ok =
             AppendMarker.create(
               directory,
               1
             )

    assert {:ok, 1} =
             GameRecordStore.append(
               store.game_records,
               fingerprint,
               {:game, 42}
             )

    assert {:ok, reopened} =
             CanonicalStore.open(
               directory,
               opts
             )

    assert CanonicalStore.find(
             reopened,
             fingerprint,
             {:game, 42}
           ) ==
             {:ok, 1}

    assert AppendMarker.read(directory) ==
             :none
  end

  test "recovers a partial fingerprint index entry", %{
    directory: directory,
    opts: opts,
    store: store
  } do
    fingerprint =
      fingerprint(1)

    assert :ok =
             AppendMarker.create(
               directory,
               1
             )

    assert {:ok, 1} =
             GameRecordStore.append(
               store.game_records,
               fingerprint,
               {:game, 42}
             )

    entry =
      <<
        fingerprint::binary,
        1::unsigned-big-64
      >>

    index_path =
      Path.join([
        directory,
        "fingerprint-index",
        "bucket-00000001.idx"
      ])

    File.write!(
      index_path,
      binary_part(
        entry,
        0,
        19
      )
    )

    assert {:ok, reopened} =
             CanonicalStore.open(
               directory,
               opts
             )

    assert CanonicalStore.find(
             reopened,
             fingerprint,
             {:game, 42}
           ) ==
             {:ok, 1}

    assert AppendMarker.read(directory) ==
             :none
  end

  test "refuses another write while an append marker exists", %{
    directory: directory,
    store: store
  } do
    assert :ok =
             AppendMarker.create(
               directory,
               1
             )

    assert CanonicalStore.put(
             store,
             fingerprint(1),
             {:game, 42}
           ) ==
             {:error,
              {
                :incomplete_append,
                1
              }}
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end
end
