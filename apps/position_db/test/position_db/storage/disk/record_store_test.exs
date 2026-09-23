defmodule PositionDB.Storage.Disk.RecordStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.Layout
  alias PositionDB.Storage.Disk.RecordStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-record-store-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    store =
      RecordStore.new(
        directory,
        record_size: 4,
        records_per_segment: 3
      )

    %{
      directory: directory,
      store: store
    }
  end

  test "reads fixed-size records from a segment", %{
    directory: directory,
    store: store
  } do
    write_segment(
      directory,
      0,
      [
        "aaaa",
        "bbbb",
        "cccc"
      ]
    )

    assert RecordStore.get(store, 1) ==
             {:ok, "aaaa"}

    assert RecordStore.get(store, 2) ==
             {:ok, "bbbb"}

    assert RecordStore.get(store, 3) ==
             {:ok, "cccc"}
  end

  test "reads from the next segment", %{
    directory: directory,
    store: store
  } do
    write_segment(
      directory,
      1,
      ["dddd"]
    )

    assert RecordStore.get(store, 4) ==
             {:ok, "dddd"}
  end

  test "returns not_found when the segment does not exist", %{
    store: store
  } do
    assert RecordStore.get(store, 1) ==
             :not_found
  end

  test "returns not_found when the record is beyond the end of the segment",
       %{
         directory: directory,
         store: store
       } do
    write_segment(
      directory,
      0,
      ["aaaa"]
    )

    assert RecordStore.get(store, 2) ==
             :not_found
  end

  test "detects a partial record", %{
    directory: directory,
    store: store
  } do
    path =
      Layout.segment_path(
        directory,
        0
      )

    File.write!(
      path,
      <<"aaaa", "bb">>
    )

    assert RecordStore.get(store, 2) ==
             {:error, :partial_record}
  end

  describe "append/3" do
    test "appends a record that can be read back", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      assert RecordStore.get(store, 1) ==
               {:ok, "aaaa"}
    end

    test "appends records sequentially", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      assert :ok =
               RecordStore.append(
                 store,
                 2,
                 "bbbb"
               )

      assert RecordStore.get(store, 1) ==
               {:ok, "aaaa"}

      assert RecordStore.get(store, 2) ==
               {:ok, "bbbb"}
    end

    test "continues in the next segment", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(store, 1, "aaaa")

      assert :ok =
               RecordStore.append(store, 2, "bbbb")

      assert :ok =
               RecordStore.append(store, 3, "cccc")

      assert :ok =
               RecordStore.append(store, 4, "dddd")

      assert RecordStore.get(store, 4) ==
               {:ok, "dddd"}
    end

    test "rejects records with the wrong size", %{
      store: store
    } do
      assert RecordStore.append(
               store,
               1,
               "aaa"
             ) ==
               {:error, :invalid_record_size}
    end

    test "rejects gaps within a segment", %{
      store: store
    } do
      assert RecordStore.append(
               store,
               2,
               "bbbb"
             ) ==
               {:error, {:unexpected_segment_size, 4, 0}}
    end

    test "does not overwrite an existing record", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      assert RecordStore.append(
               store,
               1,
               "bbbb"
             ) ==
               {:error, {:unexpected_segment_size, 0, 4}}

      assert RecordStore.get(store, 1) ==
               {:ok, "aaaa"}
    end

    test "does not start a new segment before the previous segment is full",
         %{
           store: store
         } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      assert RecordStore.append(
               store,
               4,
               "dddd"
             ) ==
               {:error, :previous_segment_incomplete}
    end
  end

  defp write_segment(
         directory,
         segment,
         records
       ) do
    path =
      Layout.segment_path(
        directory,
        segment
      )

    File.write!(
      path,
      IO.iodata_to_binary(records)
    )
  end
end
