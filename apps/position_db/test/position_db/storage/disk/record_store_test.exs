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
