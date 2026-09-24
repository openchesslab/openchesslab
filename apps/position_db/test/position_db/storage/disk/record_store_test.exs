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

    test "creates segment files at segment boundaries", %{
      directory: directory,
      store: store
    } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      first_segment =
        Layout.segment_path(
          directory,
          0
        )

      assert File.read!(first_segment) ==
               "aaaa"

      assert :ok =
               RecordStore.append(store, 2, "bbbb")

      assert :ok =
               RecordStore.append(store, 3, "cccc")

      assert :ok =
               RecordStore.append(
                 store,
                 4,
                 "dddd"
               )

      second_segment =
        Layout.segment_path(
          directory,
          1
        )

      assert File.read!(second_segment) ==
               "dddd"
    end
  end

  describe "recover_pending_append/2" do
    test "returns not_found when the pending record was not written", %{
      store: store
    } do
      assert RecordStore.recover_pending_append(
               store,
               1
             ) ==
               :not_found
    end

    test "returns a complete pending record", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(
                 store,
                 1,
                 "aaaa"
               )

      assert RecordStore.recover_pending_append(
               store,
               1
             ) ==
               {:ok, "aaaa"}

      assert RecordStore.get(
               store,
               1
             ) ==
               {:ok, "aaaa"}
    end

    test "truncates a partial pending record", %{
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

      assert RecordStore.recover_pending_append(
               store,
               2
             ) ==
               :not_found

      assert File.read!(path) ==
               "aaaa"

      assert RecordStore.cardinality(store) ==
               {:ok, 1}
    end

    test "truncates a partial pending record at a segment boundary", %{
      directory: directory,
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

      assert :ok =
               RecordStore.append(
                 store,
                 3,
                 "cccc"
               )

      path =
        Layout.segment_path(
          directory,
          1
        )

      File.write!(
        path,
        "dd"
      )

      assert RecordStore.recover_pending_append(
               store,
               4
             ) ==
               :not_found

      assert File.read!(path) ==
               ""

      assert RecordStore.cardinality(store) ==
               {:ok, 3}
    end

    test "does not truncate records beyond the pending position", %{
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
        <<"aaaa", "bbbb", "cccc">>
      )

      assert RecordStore.recover_pending_append(
               store,
               2
             ) ==
               {:error, {:unexpected_segment_size, 8, 12}}

      assert File.read!(path) ==
               <<"aaaa", "bbbb", "cccc">>
    end
  end

  describe "cardinality/1" do
    test "returns zero for an empty store", %{
      store: store
    } do
      assert RecordStore.cardinality(store) ==
               {:ok, 0}
    end

    test "counts records in the current segment", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(store, 1, "aaaa")

      assert :ok =
               RecordStore.append(store, 2, "bbbb")

      assert RecordStore.cardinality(store) ==
               {:ok, 2}
    end

    test "counts records across segments", %{
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

      assert RecordStore.cardinality(store) ==
               {:ok, 4}
    end

    test "rejects a partial final record", %{
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

      assert RecordStore.cardinality(store) ==
               {:error, {:invalid_segment_size, 0, 6}}
    end

    test "rejects an incomplete segment before a later segment", %{
      directory: directory,
      store: store
    } do
      write_segment(
        directory,
        0,
        ["aaaa", "bbbb"]
      )

      write_segment(
        directory,
        1,
        ["dddd"]
      )

      assert RecordStore.cardinality(store) ==
               {:error, {:invalid_segment_size, 0, 8}}
    end

    test "rejects gaps between segments", %{
      directory: directory,
      store: store
    } do
      write_segment(
        directory,
        0,
        ["aaaa", "bbbb", "cccc"]
      )

      write_segment(
        directory,
        2,
        ["gggg"]
      )

      assert RecordStore.cardinality(store) ==
               {:error, :non_contiguous_segments}
    end
  end

  describe "scan/1" do
    test "scans an empty store", %{
      store: store
    } do
      assert {:ok, scan} =
               RecordStore.scan(store)

      assert :done =
               RecordStore.scan_next(scan)
    end

    test "scans position ids in order", %{
      store: store
    } do
      assert :ok =
               RecordStore.append(store, 1, "aaaa")

      assert :ok =
               RecordStore.append(store, 2, "bbbb")

      assert {:ok, scan} =
               RecordStore.scan(store)

      assert {:ok, 1, scan} =
               RecordStore.scan_next(scan)

      assert {:ok, 2, scan} =
               RecordStore.scan_next(scan)

      assert :done =
               RecordStore.scan_next(scan)
    end

    test "scans across segment boundaries", %{
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

      assert {:ok, scan} =
               RecordStore.scan(store)

      assert {:ok, 1, scan} =
               RecordStore.scan_next(scan)

      assert {:ok, 2, scan} =
               RecordStore.scan_next(scan)

      assert {:ok, 3, scan} =
               RecordStore.scan_next(scan)

      assert {:ok, 4, scan} =
               RecordStore.scan_next(scan)

      assert :done =
               RecordStore.scan_next(scan)
    end

    test "refuses to scan corrupt storage", %{
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

      assert RecordStore.scan(store) ==
               {:error, {:invalid_segment_size, 0, 6}}
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
