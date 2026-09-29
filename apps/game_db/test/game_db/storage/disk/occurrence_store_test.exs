defmodule GameDB.Storage.Disk.OccurrenceStoreTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk.OccurrenceStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-occurrence-store-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, store} =
             OccurrenceStore.create(directory)

    %{
      directory: directory,
      store: store
    }
  end

  test "creates an empty occurrence store", %{
    store: store
  } do
    assert OccurrenceStore.cardinality(store) ==
             {:ok, 0}

    assert OccurrenceStore.get(
             store,
             1
           ) ==
             :not_found
  end

  test "appends all occurrences of a game in ply order", %{
    store: store
  } do
    assert {:ok, 1, 3} =
             OccurrenceStore.append(
               store,
               10,
               [
                 100,
                 200,
                 100
               ]
             )

    assert OccurrenceStore.get(
             store,
             1
           ) ==
             {:ok,
              Occurrence.new(
                1,
                10,
                0,
                100
              )}

    assert OccurrenceStore.get(
             store,
             2
           ) ==
             {:ok,
              Occurrence.new(
                2,
                10,
                1,
                200
              )}

    assert OccurrenceStore.get(
             store,
             3
           ) ==
             {:ok,
              Occurrence.new(
                3,
                10,
                2,
                100
              )}
  end

  test "allocates occurrence ids sequentially across games", %{
    store: store
  } do
    assert {:ok, 1, 2} =
             OccurrenceStore.append(
               store,
               10,
               [
                 100,
                 200
               ]
             )

    assert {:ok, 3, 2} =
             OccurrenceStore.append(
               store,
               20,
               [
                 300,
                 400
               ]
             )

    assert OccurrenceStore.get(
             store,
             3
           ) ==
             {:ok,
              Occurrence.new(
                3,
                20,
                0,
                300
              )}

    assert OccurrenceStore.get(
             store,
             4
           ) ==
             {:ok,
              Occurrence.new(
                4,
                20,
                1,
                400
              )}

    assert OccurrenceStore.cardinality(store) ==
             {:ok, 4}
  end

  test "reopens persisted occurrences", %{
    directory: directory,
    store: store
  } do
    assert {:ok, 1, 2} =
             OccurrenceStore.append(
               store,
               10,
               [
                 100,
                 200
               ]
             )

    assert {:ok, reopened} =
             OccurrenceStore.open(directory)

    assert OccurrenceStore.cardinality(reopened) ==
             {:ok, 2}

    assert OccurrenceStore.get(
             reopened,
             2
           ) ==
             {:ok,
              Occurrence.new(
                2,
                10,
                1,
                200
              )}
  end

  test "preserves repeated positions as separate occurrences", %{
    store: store
  } do
    assert {:ok, 1, 3} =
             OccurrenceStore.append(
               store,
               10,
               [
                 100,
                 200,
                 100
               ]
             )

    assert OccurrenceStore.get(
             store,
             1
           ) ==
             {:ok,
              Occurrence.new(
                1,
                10,
                0,
                100
              )}

    assert OccurrenceStore.get(
             store,
             3
           ) ==
             {:ok,
              Occurrence.new(
                3,
                10,
                2,
                100
              )}
  end

  test "requires an initial position", %{
    store: store
  } do
    assert OccurrenceStore.append(
             store,
             10,
             []
           ) ==
             {:error, :missing_initial_position}

    assert OccurrenceStore.cardinality(store) ==
             {:ok, 0}
  end

  test "rejects invalid position ids", %{
    store: store
  } do
    assert OccurrenceStore.append(
             store,
             10,
             [
               100,
               0
             ]
           ) ==
             {:error, :invalid_position_ids}

    assert OccurrenceStore.cardinality(store) ==
             {:ok, 0}
  end

  test "rejects an invalid game id", %{
    store: store
  } do
    assert OccurrenceStore.append(
             store,
             0,
             [100]
           ) ==
             {:error, :invalid_game_id}

    assert OccurrenceStore.cardinality(store) ==
             {:ok, 0}
  end

  test "detects a partial occurrence tail", %{
    store: store
  } do
    assert {:ok, 1, 1} =
             OccurrenceStore.append(
               store,
               10,
               [100]
             )

    File.write!(
      store.path,
      <<1, 2, 3>>,
      [:append]
    )

    assert OccurrenceStore.cardinality(store) ==
             {:error, :partial_record}

    assert OccurrenceStore.get(
             store,
             1
           ) ==
             {:error, :partial_record}
  end

  test "rejects a corrupt complete occurrence record", %{
    store: store
  } do
    File.write!(
      store.path,
      <<
        0::unsigned-big-64,
        0::unsigned-big-32,
        100::unsigned-big-64
      >>
    )

    assert OccurrenceStore.cardinality(store) ==
             {:ok, 1}

    assert OccurrenceStore.get(
             store,
             1
           ) ==
             {:error, :invalid_occurrence_record}
  end
end
