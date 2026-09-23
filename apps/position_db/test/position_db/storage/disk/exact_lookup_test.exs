defmodule PositionDB.Storage.Disk.ExactLookupTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.ExactLookup
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-lookup-#{System.unique_integer([:positive])}"
      )

    records_directory =
      Path.join(root, "records")

    index_directory =
      Path.join(root, "exact-index")

    File.mkdir_p!(records_directory)
    File.mkdir_p!(index_directory)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    record_store =
      RecordStore.new(
        records_directory,
        record_size: 4,
        records_per_segment: 3
      )

    exact_index =
      Disk.new(
        index_directory,
        bucket_count: 16,
        hash_size: 4,
        hash_function: &hash_key/1
      )

    %{
      record_store: record_store,
      exact_index: exact_index
    }
  end

  test "returns not_found when there are no index candidates", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert ExactLookup.find(
             record_store,
             Disk,
             exact_index,
             <<"missing">>,
             <<"aaaa">>
           ) ==
             :not_found
  end

  test "returns the id when the complete record matches", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    assert {:ok, exact_index} =
             Disk.add(
               exact_index,
               <<"a">>,
               1
             )

    assert ExactLookup.find(
             record_store,
             Disk,
             exact_index,
             <<"a">>,
             <<"aaaa">>
           ) ==
             {:ok, 1}
  end

  test "rejects a hash collision when the complete record differs", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    assert {:ok, exact_index} =
             Disk.add(
               exact_index,
               <<"collision-a">>,
               1
             )

    assert ExactLookup.find(
             record_store,
             Disk,
             exact_index,
             <<"collision-b">>,
             <<"bbbb">>
           ) ==
             :not_found
  end

  test "finds the matching record among hash collision candidates", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert :ok =
             RecordStore.append(
               record_store,
               1,
               <<"aaaa">>
             )

    assert :ok =
             RecordStore.append(
               record_store,
               2,
               <<"bbbb">>
             )

    assert {:ok, exact_index} =
             Disk.add(
               exact_index,
               <<"collision-a">>,
               1
             )

    assert {:ok, exact_index} =
             Disk.add(
               exact_index,
               <<"collision-b">>,
               2
             )

    assert ExactLookup.find(
             record_store,
             Disk,
             exact_index,
             <<"collision-b">>,
             <<"bbbb">>
           ) ==
             {:ok, 2}
  end

  test "detects an index entry pointing at a missing record", %{
    record_store: record_store,
    exact_index: exact_index
  } do
    assert {:ok, exact_index} =
             Disk.add(
               exact_index,
               <<"a">>,
               1
             )

    assert ExactLookup.find(
             record_store,
             Disk,
             exact_index,
             <<"a">>,
             <<"aaaa">>
           ) ==
             {:error, {:missing_position_record, 1}}
  end

  defp hash_key(<<"a">>),
    do: <<0, 0, 0, 1>>

  defp hash_key(<<"collision-a">>),
    do: <<0, 0, 0, 2>>

  defp hash_key(<<"collision-b">>),
    do: <<0, 0, 0, 2>>

  defp hash_key(_key),
    do: <<0, 0, 0, 15>>
end
