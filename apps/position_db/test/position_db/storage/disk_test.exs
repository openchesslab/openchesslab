defmodule PositionDB.Storage.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

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
        hash_size: 4,
        hash_function: &hash_key/1
      )

    %{
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

  defp hash_key(<<"collision-a">>) do
    <<0, 0, 0, 1>>
  end

  defp hash_key(<<"collision-b">>) do
    <<0, 0, 0, 1>>
  end

  defp hash_key(_key) do
    <<0, 0, 0, 15>>
  end
end
