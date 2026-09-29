defmodule GameDB.Storage.Disk.OccurrenceStorageTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk.GameOccurrenceIndex
  alias GameDB.Storage.Disk.OccurrenceAppendMarker
  alias GameDB.Storage.Disk.OccurrenceStorage
  alias GameDB.Storage.Disk.OccurrenceStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-occurrence-storage-#{System.unique_integer([:positive])}"
      )

    opts = [
      position_bucket_count: 4
    ]

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, storage} =
             OccurrenceStorage.create(
               directory,
               opts
             )

    %{
      directory: directory,
      opts: opts,
      storage: storage
    }
  end

  test "stores and retrieves the occurrences of a game", %{
    storage: storage
  } do
    assert :ok =
             OccurrenceStorage.append(
               storage,
               1,
               [
                 10,
                 20,
                 10
               ]
             )

    assert OccurrenceStorage.occurrences(
             storage,
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

    assert OccurrenceStorage.get_occurrence(
             storage,
             2
           ) ==
             {:ok,
              Occurrence.new(
                2,
                1,
                1,
                20
              )}
  end

  test "allocates stable occurrence ids across games", %{
    storage: storage
  } do
    assert :ok =
             OccurrenceStorage.append(
               storage,
               1,
               [
                 10,
                 20
               ]
             )

    assert :ok =
             OccurrenceStorage.append(
               storage,
               2,
               [
                 30,
                 40
               ]
             )

    assert OccurrenceStorage.occurrences(
             storage,
             2
           ) ==
             {:ok,
              [
                Occurrence.new(
                  3,
                  2,
                  0,
                  30
                ),
                Occurrence.new(
                  4,
                  2,
                  1,
                  40
                )
              ]}
  end

  test "requires sequential game ids", %{
    storage: storage
  } do
    assert OccurrenceStorage.append(
             storage,
             2,
             [10]
           ) ==
             {:error,
              {
                :unexpected_game_id,
                1,
                2
              }}
  end

  test "scans occurrences of a position incrementally", %{
    storage: storage
  } do
    assert :ok =
             OccurrenceStorage.append(
               storage,
               1,
               [
                 10,
                 20,
                 10
               ]
             )

    assert :ok =
             OccurrenceStorage.append(
               storage,
               2,
               [
                 30,
                 10
               ]
             )

    occurrences =
      storage
      |> OccurrenceStorage.scan(10)
      |> collect_scan([])

    assert MapSet.new(occurrences) ==
             MapSet.new([
               Occurrence.new(
                 1,
                 1,
                 0,
                 10
               ),
               Occurrence.new(
                 3,
                 1,
                 2,
                 10
               ),
               Occurrence.new(
                 5,
                 2,
                 1,
                 10
               )
             ])
  end

  test "finishes a scan for an unknown position", %{
    storage: storage
  } do
    scan =
      OccurrenceStorage.scan(
        storage,
        999
      )

    assert OccurrenceStorage.scan_next(scan) ==
             :done
  end

  test "reopens persisted occurrences and indexes", %{
    directory: directory,
    opts: opts,
    storage: storage
  } do
    assert :ok =
             OccurrenceStorage.append(
               storage,
               1,
               [
                 10,
                 20
               ]
             )

    assert {:ok, reopened} =
             OccurrenceStorage.open(
               directory,
               opts
             )

    assert OccurrenceStorage.occurrences(
             reopened,
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

    assert reopened
           |> OccurrenceStorage.scan(20)
           |> collect_scan([]) ==
             [
               Occurrence.new(
                 2,
                 1,
                 1,
                 20
               )
             ]
  end

  test "recovers when only the occurrence marker was persisted", %{
    directory: directory,
    opts: opts
  } do
    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               [
                 10,
                 20
               ]
             )

    assert {:ok, reopened} =
             OccurrenceStorage.open(
               directory,
               opts
             )

    assert OccurrenceStorage.occurrences(
             reopened,
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

    assert OccurrenceAppendMarker.read(directory) ==
             :none
  end

  test "recovers indexes after occurrence records were persisted", %{
    directory: directory,
    opts: opts,
    storage: storage
  } do
    position_ids =
      [
        10,
        20,
        10
      ]

    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               position_ids
             )

    assert {:ok, 1, 3} =
             OccurrenceStore.append(
               storage.occurrence_store,
               1,
               position_ids
             )

    assert {:ok, reopened} =
             OccurrenceStorage.open(
               directory,
               opts
             )

    assert OccurrenceStorage.occurrences(
             reopened,
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

    occurrences =
      reopened
      |> OccurrenceStorage.scan(10)
      |> collect_scan([])

    assert MapSet.new(occurrences) ==
             MapSet.new([
               Occurrence.new(
                 1,
                 1,
                 0,
                 10
               ),
               Occurrence.new(
                 3,
                 1,
                 2,
                 10
               )
             ])
  end

  test "recovers the position index after the game span was persisted", %{
    directory: directory,
    opts: opts,
    storage: storage
  } do
    position_ids =
      [
        10,
        20
      ]

    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               position_ids
             )

    assert {:ok, 1, 2} =
             OccurrenceStore.append(
               storage.occurrence_store,
               1,
               position_ids
             )

    assert :ok =
             GameOccurrenceIndex.append(
               storage.game_index,
               1,
               1,
               2
             )

    assert {:ok, reopened} =
             OccurrenceStorage.open(
               directory,
               opts
             )

    assert reopened
           |> OccurrenceStorage.scan(20)
           |> collect_scan([]) ==
             [
               Occurrence.new(
                 2,
                 1,
                 1,
                 20
               )
             ]

    assert OccurrenceAppendMarker.read(directory) ==
             :none
  end

  test "refuses another append while recovery is pending", %{
    directory: directory,
    storage: storage
  } do
    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               [10]
             )

    assert OccurrenceStorage.append(
             storage,
             1,
             [10]
           ) ==
             {:error,
              {
                :incomplete_append,
                1
              }}
  end

  test "detects orphan occurrence records when reopening", %{
    directory: directory,
    opts: opts,
    storage: storage
  } do
    assert {:ok, 1, 1} =
             OccurrenceStore.append(
               storage.occurrence_store,
               1,
               [10]
             )

    assert OccurrenceStorage.open(
             directory,
             opts
           ) ==
             {:error,
              {
                :orphan_occurrences,
                1
              }}
  end

  test "reports the number of games with published occurrence spans", %{
    storage: storage
  } do
    assert OccurrenceStorage.game_cardinality(storage) ==
             {:ok, 0}

    assert :ok =
             OccurrenceStorage.append(
               storage,
               1,
               [10, 20]
             )

    assert OccurrenceStorage.game_cardinality(storage) ==
             {:ok, 1}

    assert :ok =
             OccurrenceStorage.append(
               storage,
               2,
               [30]
             )

    assert OccurrenceStorage.game_cardinality(storage) ==
             {:ok, 2}
  end

  defp collect_scan(scan, reversed) do
    case OccurrenceStorage.scan_next(scan) do
      {
        :ok,
        occurrence,
        scan
      } ->
        collect_scan(
          scan,
          [
            occurrence
            | reversed
          ]
        )

      :done ->
        Enum.reverse(reversed)

      {:error, reason} ->
        flunk("unexpected scan error: #{inspect(reason)}")
    end
  end
end
