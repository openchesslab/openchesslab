defmodule GameDB.Storage.Disk.RecordStoreTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.RecordStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-record-store-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, store} =
             RecordStore.create(directory)

    %{
      directory: directory,
      store: store
    }
  end

  test "creates an empty record store", %{
    store: store
  } do
    assert RecordStore.cardinality(store) ==
             {:ok, 0}

    assert RecordStore.get(
             store,
             1
           ) ==
             :not_found
  end

  test "appends variable-length records with sequential ids", %{
    store: store
  } do
    assert {:ok, 1} =
             RecordStore.append(
               store,
               <<"a">>
             )

    assert {:ok, 2} =
             RecordStore.append(
               store,
               <<"second record">>
             )

    assert {:ok, 3} =
             RecordStore.append(
               store,
               <<"third">>
             )

    assert RecordStore.cardinality(store) ==
             {:ok, 3}

    assert RecordStore.get(
             store,
             1
           ) ==
             {:ok, <<"a">>}

    assert RecordStore.get(
             store,
             2
           ) ==
             {:ok, <<"second record">>}

    assert RecordStore.get(
             store,
             3
           ) ==
             {:ok, <<"third">>}

    assert RecordStore.get(
             store,
             4
           ) ==
             :not_found
  end

  test "reopens appended records", %{
    directory: directory,
    store: store
  } do
    assert {:ok, 1} =
             RecordStore.append(
               store,
               <<"first">>
             )

    assert {:ok, 2} =
             RecordStore.append(
               store,
               <<"second">>
             )

    assert {:ok, reopened} =
             RecordStore.open(directory)

    assert RecordStore.cardinality(reopened) ==
             {:ok, 2}

    assert RecordStore.get(
             reopened,
             1
           ) ==
             {:ok, <<"first">>}

    assert RecordStore.get(
             reopened,
             2
           ) ==
             {:ok, <<"second">>}
  end

  test "rejects empty records", %{
    store: store
  } do
    assert RecordStore.append(
             store,
             <<>>
           ) ==
             {:error, :invalid_record_size}

    assert RecordStore.cardinality(store) ==
             {:ok, 0}
  end

  test "discards an unindexed data tail when reopening", %{
    directory: directory,
    store: store
  } do
    assert {:ok, 1} =
             RecordStore.append(
               store,
               <<"first">>
             )

    data_path =
      Path.join(
        directory,
        "records.dat"
      )

    File.write!(
      data_path,
      <<"orphaned">>,
      [:append]
    )

    assert File.read!(data_path) ==
             <<"firstorphaned">>

    assert {:ok, reopened} =
             RecordStore.open(directory)

    assert File.read!(data_path) ==
             <<"first">>

    assert RecordStore.cardinality(reopened) ==
             {:ok, 1}

    assert RecordStore.get(
             reopened,
             1
           ) ==
             {:ok, <<"first">>}
  end

  test "discards a partial index entry and its data tail when reopening",
       %{
         directory: directory,
         store: store
       } do
    assert {:ok, 1} =
             RecordStore.append(
               store,
               <<"first">>
             )

    data_path =
      Path.join(
        directory,
        "records.dat"
      )

    index_path =
      Path.join(
        directory,
        "records.idx"
      )

    File.write!(
      data_path,
      <<"second">>,
      [:append]
    )

    File.write!(
      index_path,
      <<0, 0, 0, 0, 0>>,
      [:append]
    )

    assert File.stat!(index_path).size ==
             17

    assert {:ok, reopened} =
             RecordStore.open(directory)

    assert File.stat!(index_path).size ==
             12

    assert File.read!(data_path) ==
             <<"first">>

    assert RecordStore.cardinality(reopened) ==
             {:ok, 1}
  end

  test "refuses to open when indexed record data is missing",
       %{
         directory: directory,
         store: store
       } do
    assert {:ok, 1} =
             RecordStore.append(
               store,
               <<"first">>
             )

    assert {:ok, 2} =
             RecordStore.append(
               store,
               <<"second">>
             )

    data_path =
      Path.join(
        directory,
        "records.dat"
      )

    File.write!(
      data_path,
      <<"first">>
    )

    assert RecordStore.open(directory) ==
             {:error,
              {
                :truncated_data,
                11,
                5
              }}
  end
end
