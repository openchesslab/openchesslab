defmodule PositionDB.Storage.ExactIndex.Disk.BucketStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Disk.BucketStore
  alias PositionDB.Storage.ExactIndex.Disk.Entry
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    store =
      BucketStore.new(
        directory,
        hash_size: 4
      )

    %{
      directory: directory,
      store: store
    }
  end

  test "returns done for a missing bucket", %{
    store: store
  } do
    assert BucketStore.get(
             store,
             0,
             0
           ) == :done
  end

  test "reads entries by index", %{
    directory: directory,
    store: store
  } do
    hash_1 = <<1, 2, 3, 4>>
    hash_2 = <<5, 6, 7, 8>>

    write_bucket(
      directory,
      3,
      [
        Entry.encode(hash_1, 10),
        Entry.encode(hash_2, 20)
      ]
    )

    assert BucketStore.get(
             store,
             3,
             0
           ) ==
             {:ok, hash_1, 10}

    assert BucketStore.get(
             store,
             3,
             1
           ) ==
             {:ok, hash_2, 20}
  end

  test "returns done after the final entry", %{
    directory: directory,
    store: store
  } do
    write_bucket(
      directory,
      0,
      [
        Entry.encode(
          <<1, 2, 3, 4>>,
          1
        )
      ]
    )

    assert BucketStore.get(
             store,
             0,
             1
           ) == :done
  end

  test "detects a partial entry", %{
    directory: directory,
    store: store
  } do
    path =
      Layout.bucket_path(
        directory,
        0
      )

    complete =
      Entry.encode(
        <<1, 2, 3, 4>>,
        1
      )

    File.write!(
      path,
      <<
        complete::binary,
        1,
        2,
        3
      >>
    )

    assert BucketStore.get(
             store,
             0,
             1
           ) ==
             {:error, :partial_entry}
  end

  defp write_bucket(
         directory,
         bucket,
         entries
       ) do
    path =
      Layout.bucket_path(
        directory,
        bucket
      )

    File.write!(
      path,
      IO.iodata_to_binary(entries)
    )
  end
end
