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
end
