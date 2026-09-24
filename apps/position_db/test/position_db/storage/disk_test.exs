defmodule PositionDB.Storage.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk
  alias PositionDB.Storage.Disk.Manifest
  alias PositionDB.Storage.Disk.ManifestStore
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

  defmodule OtherFormatCodec do
    @behaviour PositionDB.Storage.RecordCodec

    @impl PositionDB.Storage.RecordCodec
    def format_id, do: <<"other-position-v1">>

    @impl PositionDB.Storage.RecordCodec
    def record_size, do: 4

    @impl PositionDB.Storage.RecordCodec
    def encode(_position),
      do: {:error, :not_implemented}

    @impl PositionDB.Storage.RecordCodec
    def decode(_record),
      do: {:error, :not_implemented}
  end

  defmodule WrongSizeCodec do
    @behaviour PositionDB.Storage.RecordCodec

    @impl PositionDB.Storage.RecordCodec
    def format_id, do: <<"test-position-v1">>

    @impl PositionDB.Storage.RecordCodec
    def record_size, do: 8

    @impl PositionDB.Storage.RecordCodec
    def encode(_position),
      do: {:error, :not_implemented}

    @impl PositionDB.Storage.RecordCodec
    def decode(_record),
      do: {:error, :not_implemented}
  end

  defmodule OtherFormatHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id, do: <<"other-exact-hash-v1">>

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size, do: 4

    @impl PositionDB.Storage.ExactKeyHash
    def hash(_key),
      do: {:ok, <<0, 0, 0, 1>>}
  end

  defmodule WrongSizeHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id, do: <<"test-exact-hash-v1">>

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size, do: 8

    @impl PositionDB.Storage.ExactKeyHash
    def hash(_key),
      do: {:ok, <<0, 0, 0, 0, 0, 0, 0, 1>>}
  end

  defmodule InvalidFormatCodec do
    @behaviour PositionDB.Storage.RecordCodec

    @impl PositionDB.Storage.RecordCodec
    def format_id do
      <<>>
    end

    @impl PositionDB.Storage.RecordCodec
    def record_size do
      4
    end

    @impl PositionDB.Storage.RecordCodec
    def encode(_position) do
      {:error, :not_implemented}
    end

    @impl PositionDB.Storage.RecordCodec
    def decode(_record) do
      {:error, :not_implemented}
    end
  end

  defmodule TestCodec do
    @behaviour PositionDB.Storage.RecordCodec

    @impl PositionDB.Storage.RecordCodec
    def format_id do
      <<"test-position-v1">>
    end

    @impl PositionDB.Storage.RecordCodec
    def record_size do
      4
    end

    @impl PositionDB.Storage.RecordCodec
    def encode(:position_a) do
      {:ok, <<"aaaa">>}
    end

    def encode(:position_b) do
      {:ok, <<"bbbb">>}
    end

    def encode(_position) do
      {:error, :invalid_position}
    end

    @impl PositionDB.Storage.RecordCodec
    def decode(<<"aaaa">>) do
      {:ok, :position_a}
    end

    def decode(<<"bbbb">>) do
      {:ok, :position_b}
    end

    def decode(_record) do
      {:error, :invalid_record}
    end
  end

  defmodule TestHash do
    @behaviour PositionDB.Storage.ExactKeyHash

    @impl PositionDB.Storage.ExactKeyHash
    def format_id, do: <<"test-exact-hash-v1">>

    @impl PositionDB.Storage.ExactKeyHash
    def hash_size, do: 4

    @impl PositionDB.Storage.ExactKeyHash
    def hash(<<"collision-a">>),
      do: {:ok, <<0, 0, 0, 1>>}

    def hash(<<"collision-b">>),
      do: {:ok, <<0, 0, 0, 1>>}

    def hash(_key),
      do: {:ok, <<0, 0, 0, 15>>}
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-disk-#{System.unique_integer([:positive])}"
      )

    records_directory =
      Path.join(root, "records")

    exact_index_directory =
      Path.join(root, "exact-index")

    File.mkdir_p!(records_directory)
    File.mkdir_p!(exact_index_directory)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    storage =
      Disk.new(
        root,
        codec: TestCodec,
        records_per_segment: 3,
        bucket_count: 16,
        hash: TestHash
      )

    %{
      root: root,
      storage: storage
    }
  end

  test "gets and decodes a stored position", %{
    storage: storage
  } do
    assert :ok =
             RecordStore.append(
               storage.record_store,
               1,
               <<"aaaa">>
             )

    assert Disk.get(storage, 1) ==
             {:ok, :position_a}
  end

  test "returns not_found for a missing position id", %{
    storage: storage
  } do
    assert Disk.get(storage, 1) ==
             :not_found
  end

  test "finds the matching position among hash collision candidates",
       %{
         storage: storage
       } do
    assert :ok =
             RecordStore.append(
               storage.record_store,
               1,
               <<"aaaa">>
             )

    assert :ok =
             RecordStore.append(
               storage.record_store,
               2,
               <<"bbbb">>
             )

    assert {:ok, exact_index} =
             ExactIndex.add(
               storage.exact_index,
               <<"collision-a">>,
               1
             )

    assert {:ok, exact_index} =
             ExactIndex.add(
               exact_index,
               <<"collision-b">>,
               2
             )

    storage =
      %{storage | exact_index: exact_index}

    assert Disk.find(
             storage,
             <<"collision-b">>,
             :position_b
           ) ==
             {:ok, 2}
  end

  test "returns not_found when hash candidates contain a different position",
       %{
         storage: storage
       } do
    assert :ok =
             RecordStore.append(
               storage.record_store,
               1,
               <<"aaaa">>
             )

    assert {:ok, exact_index} =
             ExactIndex.add(
               storage.exact_index,
               <<"collision-a">>,
               1
             )

    storage =
      %{storage | exact_index: exact_index}

    assert Disk.find(
             storage,
             <<"collision-b">>,
             :position_b
           ) ==
             :not_found
  end

  test "propagates record decode errors", %{
    storage: storage
  } do
    assert :ok =
             RecordStore.append(
               storage.record_store,
               1,
               <<"xxxx">>
             )

    assert Disk.get(storage, 1) ==
             {:error, :invalid_record}
  end

  test "propagates position encode errors", %{
    storage: storage
  } do
    assert Disk.find(
             storage,
             <<"a">>,
             :not_a_position
           ) ==
             {:error, :invalid_position}
  end

  test "returns persisted cardinality", %{
    storage: storage
  } do
    assert Disk.cardinality(storage) ==
             {:ok, 0}

    assert :ok =
             RecordStore.append(
               storage.record_store,
               1,
               <<"aaaa">>
             )

    assert :ok =
             RecordStore.append(
               storage.record_store,
               2,
               <<"bbbb">>
             )

    assert Disk.cardinality(storage) ==
             {:ok, 2}
  end

  describe "create/2" do
    test "creates an empty disk store and persists its manifest", %{
      root: root
    } do
      directory =
        Path.join(
          root,
          "created"
        )

      assert {:ok, storage} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 records_per_segment: 3,
                 bucket_count: 16,
                 hash: TestHash
               )

      assert File.dir?(
               Path.join(
                 directory,
                 "records"
               )
             )

      assert File.dir?(
               Path.join(
                 directory,
                 "exact-index"
               )
             )

      assert ManifestStore.read(directory) ==
               {:ok,
                %Manifest{
                  record_format_id: <<"test-position-v1">>,
                  record_size: 4,
                  records_per_segment: 3,
                  exact_hash_format_id: <<"test-exact-hash-v1">>,
                  exact_hash_size: 4,
                  exact_bucket_count: 16
                }}

      assert Disk.cardinality(storage) ==
               {:ok, 0}
    end

    test "refuses to create storage in an existing directory", %{
      root: root
    } do
      directory =
        Path.join(
          root,
          "existing"
        )

      File.mkdir!(directory)

      assert Disk.create(
               directory,
               codec: TestCodec,
               records_per_segment: 3,
               bucket_count: 16,
               hash: TestHash
             ) ==
               {:error, :storage_exists}

      assert ManifestStore.read(directory) ==
               {:error, :manifest_not_found}
    end

    test "does not overwrite an existing disk store", %{
      root: root
    } do
      directory =
        Path.join(
          root,
          "created"
        )

      assert {:ok, _storage} =
               Disk.create(
                 directory,
                 codec: TestCodec,
                 records_per_segment: 3,
                 bucket_count: 16,
                 hash: TestHash
               )

      assert {:ok, original_manifest} =
               ManifestStore.read(directory)

      assert Disk.create(
               directory,
               codec: TestCodec,
               records_per_segment: 999,
               bucket_count: 32,
               hash: TestHash
             ) ==
               {:error, :storage_exists}

      assert ManifestStore.read(directory) ==
               {:ok, original_manifest}
    end

    test "validates the manifest before creating the storage directory", %{
      root: root
    } do
      directory =
        Path.join(
          root,
          "invalid"
        )

      assert Disk.create(
               directory,
               codec: InvalidFormatCodec,
               records_per_segment: 3,
               bucket_count: 16,
               hash: TestHash
             ) ==
               {:error, :invalid_manifest}

      refute File.exists?(directory)
    end
  end
end
