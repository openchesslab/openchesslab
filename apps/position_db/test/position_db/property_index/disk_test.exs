defmodule PositionDB.PropertyIndex.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.PropertyIndex.Disk
  alias PositionDB.Storage.Disk.IndexProgressStore
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout
  alias PositionDB.Storage.PostingIndex.Disk.Manifest
  alias PositionDB.Storage.PostingIndex.Disk.ManifestStore

  defmodule TestCodec do
    @behaviour PositionDB.Storage.PropertyKeyCodec

    @impl PositionDB.Storage.PropertyKeyCodec
    def format_id do
      <<"test-property-v1">>
    end

    @impl PositionDB.Storage.PropertyKeyCodec
    def encode(
          :color,
          :white
        ) do
      {:ok, <<1, 1>>}
    end

    def encode(
          :color,
          :black
        ) do
      {:ok, <<1, 2>>}
    end

    def encode(
          :selected,
          true
        ) do
      {:ok, <<2, 1>>}
    end

    def encode(
          _property,
          _value
        ) do
      {:error, :unsupported_property}
    end
  end

  defmodule OtherFormatCodec do
    @behaviour PositionDB.Storage.PropertyKeyCodec

    @impl PositionDB.Storage.PropertyKeyCodec
    def format_id do
      <<"other-property-v1">>
    end

    @impl PositionDB.Storage.PropertyKeyCodec
    def encode(
          :color,
          :white
        ) do
      {:ok, <<1, 1>>}
    end

    def encode(
          _property,
          _value
        ) do
      {:error, :unsupported_property}
    end
  end

  defmodule InvalidFormatCodec do
    @behaviour PositionDB.Storage.PropertyKeyCodec

    @impl PositionDB.Storage.PropertyKeyCodec
    def format_id do
      <<>>
    end

    @impl PositionDB.Storage.PropertyKeyCodec
    def encode(
          _property,
          _value
        ) do
      {:error, :unsupported_property}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-property-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    directory =
      Path.join(
        root,
        "index"
      )

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    %{
      root: root,
      directory: directory
    }
  end

  describe "create/2" do
    test "creates an empty persistent property index", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 16
               )

      assert Disk.indexed_through(index) == 0

      assert {:ok, manifest} =
               ManifestStore.read(directory)

      assert manifest ==
               %Manifest{
                 key_format_id: <<"test-property-v1">>,
                 bucket_count: 16
               }

      assert IndexProgressStore.read(directory) ==
               {:ok, 0}
    end

    test "does not overwrite an existing property index", %{
      directory: directory
    } do
      assert {:ok, _index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 16
               )

      assert Disk.create(
               directory,
               codec: TestCodec,
               bucket_count: 32
             ) ==
               {:error, :property_index_exists}
    end

    test "validates the manifest before creating the directory", %{
      directory: directory
    } do
      assert Disk.create(
               directory,
               codec: InvalidFormatCodec,
               bucket_count: 16
             ) ==
               {:error, :invalid_posting_manifest}

      refute File.exists?(directory)
    end
  end

  describe "open/2" do
    test "reopens using the persisted bucket layout", %{
      directory: directory
    } do
      assert {:ok, _created} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 16
               )

      assert {:ok, reopened} =
               Disk.open(
                 directory,
                 codec: TestCodec
               )

      assert reopened.posting_index.bucket_count ==
               16

      assert Disk.indexed_through(reopened) == 0
    end

    test "rejects a different property-key format", %{
      directory: directory
    } do
      assert {:ok, _created} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 16
               )

      assert Disk.open(
               directory,
               codec: OtherFormatCodec
             ) ==
               {:error,
                {:property_index_format_mismatch, :key_format_id, <<"test-property-v1">>,
                 <<"other-property-v1">>}}
    end

    test "requires durable progress metadata", %{
      directory: directory
    } do
      File.mkdir!(directory)

      assert :ok =
               ManifestStore.create(
                 directory,
                 %Manifest{
                   key_format_id: <<"test-property-v1">>,
                   bucket_count: 16
                 }
               )

      assert Disk.open(
               directory,
               codec: TestCodec
             ) ==
               {:error, :property_index_progress_not_found}
    end
  end

  describe "postings" do
    test "adds and looks up property postings", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 2
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :black},
                 3
               )

      assert Disk.lookup(
               index,
               {:color, :white}
             ) ==
               {:ok, [1, 2]}

      assert Disk.lookup(
               index,
               {:color, :black}
             ) ==
               {:ok, [3]}

      assert Disk.cardinality(
               index,
               {:color, :white}
             ) ==
               {:ok, 2}
    end

    test "adding the same posting is idempotent", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 1
               )

      assert Disk.lookup(
               index,
               {:color, :white}
             ) ==
               {:ok, [1]}
    end

    test "persists postings across reopen", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 16
               )

      assert {:ok, _index} =
               Disk.add(
                 index,
                 {:selected, true},
                 42
               )

      assert {:ok, reopened} =
               Disk.open(
                 directory,
                 codec: TestCodec
               )

      assert Disk.lookup(
               reopened,
               {:selected, true}
             ) ==
               {:ok, [42]}
    end

    test "propagates property encoding errors", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert Disk.add(
               index,
               {:unknown, :value},
               1
             ) ==
               {:error, :unsupported_property}
    end
  end

  describe "progress" do
    test "posting writes do not advance durable progress", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 1
               )

      assert Disk.indexed_through(index) == 0

      assert IndexProgressStore.read(directory) ==
               {:ok, 0}
    end

    test "advances progress only when explicitly committed", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, index} =
               Disk.add(
                 index,
                 {:color, :white},
                 1
               )

      assert {:ok, index} =
               Disk.advance(
                 index,
                 1
               )

      assert Disk.indexed_through(index) == 1

      assert IndexProgressStore.read(directory) ==
               {:ok, 1}

      assert {:ok, reopened} =
               Disk.open(
                 directory,
                 codec: TestCodec
               )

      assert Disk.indexed_through(reopened) == 1
    end

    test "does not allow durable progress to move backwards", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, index} =
               Disk.advance(
                 index,
                 10
               )

      assert Disk.advance(
               index,
               9
             ) ==
               {:error, {:indexed_through_regression, 10, 9}}
    end
  end

  describe "recovery" do
    test "recovers an interrupted property posting", %{
      directory: directory
    } do
      assert {:ok, index} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 bucket_count: 1
               )

      assert {:ok, key} =
               TestCodec.encode(
                 :color,
                 :white
               )

      entry =
        Entry.encode(
          key,
          1
        )

      path =
        Layout.bucket_path(
          directory,
          0
        )

      File.write!(
        path,
        binary_part(
          entry,
          0,
          5
        )
      )

      assert {:ok, index} =
               Disk.recover_add(
                 index,
                 {:color, :white},
                 1
               )

      assert Disk.lookup(
               index,
               {:color, :white}
             ) ==
               {:ok, [1]}

      assert Disk.indexed_through(index) == 0
    end
  end
end
