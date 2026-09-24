defmodule PositionDB.Storage.PostingIndex.Disk.BucketStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.BucketStore
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-posting-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory,
      store: BucketStore.new(directory)
    }
  end

  describe "append_durable/4" do
    test "appends posting entries to a bucket", %{
      directory: directory,
      store: store
    } do
      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 <<"key-a">>,
                 10
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 <<"a-longer-key">>,
                 20
               )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      assert File.read!(path) ==
               <<
                 Entry.encode(
                   <<"key-a">>,
                   10
                 )::binary,
                 Entry.encode(
                   <<"a-longer-key">>,
                   20
                 )::binary
               >>
    end
  end

  describe "lookup/3" do
    test "returns no postings for a missing bucket", %{
      store: store
    } do
      assert BucketStore.lookup(
               store,
               3,
               <<"missing">>
             ) ==
               {:ok, []}
    end

    test "reads variable-size entries sequentially", %{
      store: store
    } do
      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 <<"a">>,
                 10
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 <<"a-much-longer-key">>,
                 20
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 3,
                 <<"a">>,
                 30
               )

      assert BucketStore.lookup(
               store,
               3,
               <<"a">>
             ) ==
               {:ok, [10, 30]}

      assert BucketStore.lookup(
               store,
               3,
               <<"a-much-longer-key">>
             ) ==
               {:ok, [20]}
    end

    test "compares the complete key inside a bucket", %{
      store: store
    } do
      assert :ok =
               BucketStore.append_durable(
                 store,
                 7,
                 <<"collision-a">>,
                 10
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 7,
                 <<"collision-b">>,
                 20
               )

      assert BucketStore.lookup(
               store,
               7,
               <<"collision-a">>
             ) ==
               {:ok, [10]}

      assert BucketStore.lookup(
               store,
               7,
               <<"collision-b">>
             ) ==
               {:ok, [20]}
    end

    test "supports an empty binary key", %{
      store: store
    } do
      assert :ok =
               BucketStore.append_durable(
                 store,
                 1,
                 <<>>,
                 10
               )

      assert :ok =
               BucketStore.append_durable(
                 store,
                 1,
                 <<"other">>,
                 20
               )

      assert BucketStore.lookup(
               store,
               1,
               <<>>
             ) ==
               {:ok, [10]}
    end

    test "detects a partial header", %{
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
        <<0, 0, 0>>
      )

      assert BucketStore.lookup(
               store,
               0,
               <<"key">>
             ) ==
               {:error, :partial_entry}
    end

    test "detects a partial key", %{
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
        <<
          5::unsigned-big-32,
          1::unsigned-big-64,
          "abc"
        >>
      )

      assert BucketStore.lookup(
               store,
               0,
               <<"abcde">>
             ) ==
               {:error, :partial_entry}
    end

    test "rejects an invalid position id in a stored entry", %{
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
        <<
          3::unsigned-big-32,
          0::unsigned-big-64,
          "abc"
        >>
      )

      assert BucketStore.lookup(
               store,
               0,
               <<"abc">>
             ) ==
               {:error, :invalid_position_id}
    end
  end

  describe "recover_pending_append/4" do
    test "restores an entry when the bucket does not exist", %{
      directory: directory,
      store: store
    } do
      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 <<"key-a">>,
                 10
               )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      assert File.read!(path) ==
               Entry.encode(
                 <<"key-a">>,
                 10
               )
    end

    test "does not duplicate an already complete pending entry", %{
      directory: directory,
      store: store
    } do
      entry =
        Entry.encode(
          <<"key-a">>,
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
                 <<"key-a">>,
                 10
               )

      assert File.read!(path) ==
               entry
    end

    test "appends when the position id exists under a different key", %{
      directory: directory,
      store: store
    } do
      previous =
        Entry.encode(
          <<"collision-a">>,
          10
        )

      pending =
        Entry.encode(
          <<"collision-b">>,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        previous
      )

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 <<"collision-b">>,
                 10
               )

      assert File.read!(path) ==
               <<
                 previous::binary,
                 pending::binary
               >>
    end

    test "replaces a matching partial header with the complete pending entry",
         %{
           directory: directory,
           store: store
         } do
      previous =
        Entry.encode(
          <<"previous">>,
          9
        )

      pending =
        Entry.encode(
          <<"key-a">>,
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
                 <<"key-a">>,
                 10
               )

      assert File.read!(path) ==
               <<
                 previous::binary,
                 pending::binary
               >>
    end

    test "replaces a matching partial key with the complete pending entry",
         %{
           directory: directory,
           store: store
         } do
      previous =
        Entry.encode(
          <<"previous">>,
          9
        )

      pending =
        Entry.encode(
          <<"a-longer-key">>,
          10
        )

      partial_size =
        Entry.header_size() + 4

      partial =
        binary_part(
          pending,
          0,
          partial_size
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
                 <<"a-longer-key">>,
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
      previous =
        Entry.encode(
          <<"previous">>,
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
               <<"key-a">>,
               10
             ) ==
               {:error, :unexpected_partial_entry}

      assert File.read!(path) ==
               corrupted
    end

    test "appends the pending entry to an existing complete bucket", %{
      directory: directory,
      store: store
    } do
      previous =
        Entry.encode(
          <<"previous">>,
          9
        )

      pending =
        Entry.encode(
          <<"key-a">>,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        previous
      )

      assert :ok =
               BucketStore.recover_pending_append(
                 store,
                 3,
                 <<"key-a">>,
                 10
               )

      assert File.read!(path) ==
               <<
                 previous::binary,
                 pending::binary
               >>
    end
  end

  describe "recover_pending_appends/3" do
    test "recovers a later partial posting when an earlier expected posting is in the same bucket",
         %{
           directory: directory,
           store: store
         } do
      first =
        Entry.encode(
          <<"first">>,
          10
        )

      second =
        Entry.encode(
          <<"second">>,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        <<
          first::binary,
          binary_part(
            second,
            0,
            5
          )::binary
        >>
      )

      assert :ok =
               BucketStore.recover_pending_appends(
                 store,
                 3,
                 [
                   {<<"first">>, 10},
                   {<<"second">>, 10}
                 ]
               )

      assert File.read!(path) ==
               <<
                 first::binary,
                 second::binary
               >>
    end

    test "restores all missing expected postings after a matching partial tail",
         %{
           directory: directory,
           store: store
         } do
      first =
        Entry.encode(
          <<"first">>,
          10
        )

      second =
        Entry.encode(
          <<"second">>,
          10
        )

      third =
        Entry.encode(
          <<"third">>,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      File.write!(
        path,
        <<
          first::binary,
          binary_part(
            second,
            0,
            7
          )::binary
        >>
      )

      assert :ok =
               BucketStore.recover_pending_appends(
                 store,
                 3,
                 [
                   {<<"first">>, 10},
                   {<<"second">>, 10},
                   {<<"third">>, 10}
                 ]
               )

      assert File.read!(path) ==
               <<
                 first::binary,
                 second::binary,
                 third::binary
               >>
    end

    test "refuses a partial tail unrelated to every expected posting",
         %{
           directory: directory,
           store: store
         } do
      first =
        Entry.encode(
          <<"first">>,
          10
        )

      path =
        Layout.bucket_path(
          directory,
          3
        )

      corrupted =
        <<
          first::binary,
          255,
          254,
          253
        >>

      File.write!(
        path,
        corrupted
      )

      assert BucketStore.recover_pending_appends(
               store,
               3,
               [
                 {<<"first">>, 10},
                 {<<"second">>, 10}
               ]
             ) ==
               {:error, :unexpected_partial_entry}

      assert File.read!(path) ==
               corrupted
    end
  end
end
