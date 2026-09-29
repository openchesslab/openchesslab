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

  test "stores a complete game insert", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert {:ok, storage, 1} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10, 20, 10]
             )

    assert CanonicalStore.get(storage.canonical_store, 1) ==
             {:ok, {:game, 42}}

    assert OccurrenceStorage.occurrences(storage.occurrence_storage, 1) ==
             {:ok,
              [
                Occurrence.new(1, 1, 0, 10),
                Occurrence.new(2, 1, 1, 20),
                Occurrence.new(3, 1, 2, 10)
              ]}

    assert GameInsertMarker.read(directory) == :none
  end

  test "returns the existing id without duplicating occurrences", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert {:ok, storage, 1} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10, 20]
             )

    assert {:ok, storage, 1} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10, 20]
             )

    assert CanonicalStore.cardinality(storage.canonical_store) ==
             {:ok, 1}

    assert OccurrenceStorage.occurrences(storage.occurrence_storage, 1) ==
             {:ok,
              [
                Occurrence.new(1, 1, 0, 10),
                Occurrence.new(2, 1, 1, 20)
              ]}
  end

  test "rejects invalid position ids before starting an insert", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert Disk.put(
             storage,
             fingerprint(1),
             {:game, 42},
             []
           ) ==
             {:error, :missing_initial_position}

    assert Disk.put(
             storage,
             fingerprint(1),
             {:game, 42},
             [10, 0]
           ) ==
             {:error, :invalid_position_ids}

    assert GameInsertMarker.read(directory) == :none

    assert CanonicalStore.cardinality(storage.canonical_store) ==
             {:ok, 0}
  end

  test "refuses another insert while outer recovery is pending", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [10, 20]
             )

    assert Disk.put(
             storage,
             fingerprint(1),
             {:game, 42},
             [10, 20]
           ) ==
             {:error, {:incomplete_game_insert, 1}}

    assert CanonicalStore.cardinality(storage.canonical_store) ==
             {:ok, 0}
  end

  test "implements the GameDB storage contract", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert {:ok, storage, game_1} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10, 20, 10]
             )

    assert {:ok, storage, game_2} =
             Disk.put(
               storage,
               fingerprint(2),
               {:game, 84},
               [30, 10]
             )

    db = GameDB.new(Disk, storage)

    assert GameDB.cardinality(db) == 2

    assert GameDB.find(db, fingerprint(1), {:game, 42}) ==
             {:ok, game_1}

    assert GameDB.get(db, game_2) ==
             {:ok, {:game, 84}}

    assert GameDB.occurrences(db, game_1) ==
             {:ok,
              [
                Occurrence.new(1, game_1, 0, 10),
                Occurrence.new(2, game_1, 1, 20),
                Occurrence.new(3, game_1, 2, 10)
              ]}

    assert GameDB.get_occurrence(db, 4) ==
             {:ok, Occurrence.new(4, game_2, 0, 30)}

    assert {:ok, occurrences} =
             GameDB.occurrences_by_position_id(
               db,
               10
             )

    assert MapSet.new(occurrences) ==
             MapSet.new([
               Occurrence.new(1, game_1, 0, 10),
               Occurrence.new(3, game_1, 2, 10),
               Occurrence.new(5, game_2, 1, 10)
             ])
  end

  test "scans position occurrences incrementally through GameDB", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert {:ok, storage, game_id} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10, 20, 10]
             )

    db = GameDB.new(Disk, storage)

    scan = GameDB.scan_occurrences(db, 10)

    assert {:ok, first, scan} =
             GameDB.scan_occurrences_next(scan)

    assert {:ok, second, scan} =
             GameDB.scan_occurrences_next(scan)

    assert :done =
             GameDB.scan_occurrences_next(scan)

    assert MapSet.new([first, second]) ==
             MapSet.new([
               Occurrence.new(1, game_id, 0, 10),
               Occurrence.new(3, game_id, 2, 10)
             ])
  end

  test "restores game cardinality when reopened", %{
    directory: directory,
    opts: opts
  } do
    assert {:ok, storage} = Disk.create(directory, opts)

    assert Disk.cardinality(storage) == 0

    assert {:ok, storage, 1} =
             Disk.put(
               storage,
               fingerprint(1),
               {:game, 42},
               [10]
             )

    assert Disk.cardinality(storage) == 1

    assert {:ok, reopened} =
             Disk.open(
               directory,
               opts
             )

    assert Disk.cardinality(reopened) == 1

    assert {:ok, 1, scan} =
             reopened
             |> Disk.scan()
             |> Disk.scan_next()

    assert Disk.scan_next(scan) == :done
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end
end
