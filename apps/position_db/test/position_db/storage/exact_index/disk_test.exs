defmodule PositionDB.Storage.ExactIndex.DiskTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Disk
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-exact-index-disk-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    opts = [
      bucket_count: 16,
      hash_size: 4,
      hash_function: &hash_key/1
    ]

    index =
      Disk.new(
        directory,
        opts
      )

    %{
      directory: directory,
      index: index,
      opts: opts
    }
  end

  test "returns no candidates for an unknown key", %{
    index: index
  } do
    assert Disk.lookup(
             index,
             <<"missing">>
           ) ==
             {:ok, []}
  end

  test "adds and finds a candidate", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "survives reopening the index", %{
    directory: directory,
    index: index,
    opts: opts
  } do
    assert {:ok, _index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    reopened =
      Disk.new(
        directory,
        opts
      )

    assert Disk.lookup(
             reopened,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "does not add the same candidate twice", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}
  end

  test "keeps different hashes separate", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"b">>,
               20
             )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:ok, [10]}

    assert Disk.lookup(
             index,
             <<"b">>
           ) ==
             {:ok, [20]}
  end

  test "returns all candidates when different keys have the same hash", %{
    index: index
  } do
    assert {:ok, index} =
             Disk.add(
               index,
               <<"collision-a">>,
               10
             )

    assert {:ok, index} =
             Disk.add(
               index,
               <<"collision-b">>,
               20
             )

    assert Disk.lookup(
             index,
             <<"collision-a">>
           ) ==
             {:ok, [10, 20]}

    assert Disk.lookup(
             index,
             <<"collision-b">>
           ) ==
             {:ok, [10, 20]}
  end

  test "propagates bucket corruption", %{
    directory: directory,
    index: index
  } do
    hash =
      hash_key(<<"a">>)

    bucket =
      Layout.bucket(
        hash,
        16
      )

    path =
      Layout.bucket_path(
        directory,
        bucket
      )

    File.write!(
      path,
      <<1, 2, 3>>
    )

    assert Disk.lookup(
             index,
             <<"a">>
           ) ==
             {:error, :partial_entry}
  end

  defp hash_key(<<"a">>),
    do: <<0, 0, 0, 1>>

  defp hash_key(<<"b">>),
    do: <<0, 0, 0, 2>>

  defp hash_key(<<"collision-a">>),
    do: <<0, 0, 0, 3>>

  defp hash_key(<<"collision-b">>),
    do: <<0, 0, 0, 3>>

  defp hash_key(_key),
    do: <<0, 0, 0, 15>>
end
