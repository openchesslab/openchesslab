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

  describe "append/4" do
    test "appends an entry that can be read back", %{
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash,
                 10
               )

      assert BucketStore.get(
               store,
               3,
               0
             ) ==
               {:ok, hash, 10}
    end

    test "appends multiple entries to the same bucket", %{
      store: store
    } do
      hash_1 = <<1, 2, 3, 4>>
      hash_2 = <<5, 6, 7, 8>>

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash_1,
                 10
               )

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash_2,
                 20
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

    test "keeps buckets separate", %{
      store: store
    } do
      hash_1 = <<1, 2, 3, 4>>
      hash_2 = <<5, 6, 7, 8>>

      assert :ok =
               BucketStore.append(
                 store,
                 1,
                 hash_1,
                 10
               )

      assert :ok =
               BucketStore.append(
                 store,
                 2,
                 hash_2,
                 20
               )

      assert BucketStore.get(
               store,
               1,
               0
             ) ==
               {:ok, hash_1, 10}

      assert BucketStore.get(
               store,
               2,
               0
             ) ==
               {:ok, hash_2, 20}
    end

    test "rejects hashes with the wrong size", %{
      store: store
    } do
      assert BucketStore.append(
               store,
               0,
               <<1, 2, 3>>,
               1
             ) ==
               {:error, :invalid_hash_size}
    end

    test "does not append to a bucket containing a partial entry", %{
      directory: directory,
      store: store
    } do
      path =
        Layout.bucket_path(
          directory,
          0
        )

      File.write!(
        path,
        <<1, 2, 3>>
      )

      assert BucketStore.append(
               store,
               0,
               <<1, 2, 3, 4>>,
               1
             ) ==
               {:error, :partial_entry}

      assert File.read!(path) ==
               <<1, 2, 3>>
    end
  end

  describe "append_durable/4" do
    test "durably appends an entry to a new bucket", %{
      directory: directory,
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 hash,
                 10
               )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      assert File.read!(path) ==
               Entry.encode(
                 hash,
                 10
               )

      assert BucketStore.get(
               store,
               3,
               0
             ) ==
               {:ok, hash, 10}
    end

    test "durably appends to an existing bucket", %{
      store: store
    } do
      hash_1 = <<1, 2, 3, 4>>
      hash_2 = <<5, 6, 7, 8>>

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 hash_1,
                 10
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 hash_2,
                 20
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

    test "does not durably append to a bucket containing a partial entry", %{
      directory: directory,
      store: store
    } do
      path =
        Layout.bucket_path(
          directory,
          0
        )

      File.write!(
        path,
        <<1, 2, 3>>
      )

      assert BucketStore.append_durable(
               store,
               0,
               <<1, 2, 3, 4>>,
               1
             ) ==
               {:error, :partial_entry}

      assert File.read!(path) ==
               <<1, 2, 3>>
    end
  end

  describe "lookup/3" do
    test "returns no candidates for a missing bucket", %{
      store: store
    } do
      assert BucketStore.lookup(
               store,
               3,
               <<1, 2, 3, 4>>
             ) ==
               {:ok, []}
    end

    test "returns ids whose complete hash matches", %{
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash,
                 10
               )

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 <<1, 2, 3, 5>>,
                 20
               )

      assert BucketStore.lookup(
               store,
               3,
               hash
             ) ==
               {:ok, [10]}
    end

    test "returns multiple candidates for the same hash", %{
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash,
                 10
               )

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 hash,
                 20
               )

      assert BucketStore.lookup(
               store,
               3,
               hash
             ) ==
               {:ok, [10, 20]}
    end

    test "rejects hashes with the wrong size", %{
      store: store
    } do
      assert BucketStore.lookup(
               store,
               0,
               <<1, 2, 3>>
             ) ==
               {:error, :invalid_hash_size}
    end

    test "detects a partial entry during lookup", %{
      directory: directory,
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      path =
        Layout.bucket_path(
          directory,
          0
        )

      File.write!(
        path,
        <<
          Entry.encode(hash, 1)::binary,
          1,
          2,
          3
        >>
      )

      assert BucketStore.lookup(
               store,
               0,
               hash
             ) ==
               {:error, :partial_entry}
    end
  end

  describe "recover_pending_append/4" do
    test "restores an entry when the bucket does not exist", %{
      directory: directory,
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 hash,
                 10
               )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      assert File.read!(path) ==
               Entry.encode(
                 hash,
                 10
               )
    end

    test "does not duplicate an already complete pending entry", %{
      directory: directory,
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      entry =
        Entry.encode(
          hash,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        entry
      )

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 hash,
                 10
               )

      assert File.read!(path) ==
               entry
    end

    test "replaces a matching partial tail with the complete pending entry",
         %{
           directory: directory,
           store: store
         } do
      hash = <<1, 2, 3, 4>>

      previous =
        Entry.encode(
          <<5, 6, 7, 8>>,
          9
        )

      pending =
        Entry.encode(
          hash,
          10
        )

      partial =
        binary_part(
          pending,
          0,
          5
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        <<
          previous::binary,
          partial::binary
        >>
      )

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 hash,
                 10
               )

      assert File.read!(path) ==
               <<
                 previous::binary,
                 pending::binary
               >>
    end

    test "refuses to truncate an unrelated partial tail", %{
      directory: directory,
      store: store
    } do
      hash = <<1, 2, 3, 4>>

      previous =
        Entry.encode(
          <<5, 6, 7, 8>>,
          9
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      corrupted =
        <<
          previous::binary,
          255,
          254,
          253
        >>

      File.write!(
        path,
        corrupted
      )

      assert BucketStore.recover_pending_append(
               store,
               3,
               hash,
               10
             ) ==
               {:error, :unexpected_partial_entry}

      assert File.read!(path) ==
               corrupted
    end

    test "appends the pending entry to an existing complete bucket", %{
      store: store
    } do
      previous_hash =
        <<5, 6, 7, 8>>

      pending_hash =
        <<1, 2, 3, 4>>

      assert :ok =
               BucketStore.append(
                 store,
                 3,
                 previous_hash,
                 9
               )

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 pending_hash,
                 10
               )

      assert BucketStore.get(
               store,
               3,
               0
             ) ==
               {:ok, previous_hash, 9}

      assert BucketStore.get(
               store,
               3,
               1
             ) ==
               {:ok, pending_hash, 10}
    end
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
