defmodule GameDB.Storage.DiskTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk
  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameInsertMarker
  alias GameDB.Storage.Disk.OccurrenceStorage

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
        "game-db-disk-#{System.unique_integer([:positive])}"
      )

    opts = [
      codec: TestCodec,
      bucket_count: 4,
      position_bucket_count: 4
    ]

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory,
      opts: opts
    }
  end

  test "creates canonical and occurrence storage", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} =
             Disk.create(
               directory,
               opts
             )

    assert %Disk{} = storage
    assert %CanonicalStore{} = storage.canonical_store
    assert %OccurrenceStorage{} = storage.occurrence_storage

    assert File.dir?(
             Path.join(
               directory,
               "canonical"
             )
           )

    assert File.dir?(
             Path.join(
               directory,
               "occurrences"
             )
           )
  end

  test "refuses to create storage over an existing directory", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, _storage} =
             Disk.create(
               directory,
               opts
             )

    assert Disk.create(
             directory,
             opts
           ) ==
             {:error, :storage_exists}
  end

  test "reopens both component stores", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} =
             Disk.create(
               directory,
               opts
             )

    assert {:ok, canonical_store, 1} =
             CanonicalStore.put(
               storage.canonical_store,
               fingerprint(1),
               {:game, 42}
             )

    assert :ok =
             OccurrenceStorage.append(
               storage.occurrence_storage,
               1,
               [
                 10,
                 20
               ]
             )

    storage = %{
      storage
      | canonical_store: canonical_store
    }

    assert {:ok, reopened} =
             Disk.open(
               directory,
               opts
             )

    assert CanonicalStore.get(
             reopened.canonical_store,
             1
           ) ==
             {:ok, {:game, 42}}

    assert OccurrenceStorage.occurrences(
             reopened.occurrence_storage,
             1
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  1,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  1,
                  1,
                  20
                )
              ]}

    assert storage.directory ==
             reopened.directory
  end

  test "recovers a game insert after the canonical game was published", %{
    directory: directory,
    opts: opts
  } do
    position_ids =
      [
        10,
        20,
        10
      ]

    assert {:ok, storage} =
             Disk.create(
               directory,
               opts
             )

    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               position_ids
             )

    assert {:ok, _canonical_store, 1} =
             CanonicalStore.put(
               storage.canonical_store,
               fingerprint(1),
               {:game, 42}
             )

    assert {:ok, reopened} =
             Disk.open(
               directory,
               opts
             )

    assert OccurrenceStorage.occurrences(
             reopened.occurrence_storage,
             1
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  1,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  1,
                  1,
                  20
                ),
                Occurrence.new(
                  3,
                  1,
                  2,
                  10
                )
              ]}

    assert GameInsertMarker.read(directory) ==
             :none
  end

  test "clears an insert that crashed before publishing the canonical game", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, _storage} =
             Disk.create(
               directory,
               opts
             )

    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [
                 10,
                 20
               ]
             )

    assert {:ok, reopened} =
             Disk.open(
               directory,
               opts
             )

    assert CanonicalStore.cardinality(reopened.canonical_store) ==
             {:ok, 0}

    assert OccurrenceStorage.occurrences(
             reopened.occurrence_storage,
             1
           ) ==
             :not_found

    assert GameInsertMarker.read(directory) ==
             :none
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end
end
