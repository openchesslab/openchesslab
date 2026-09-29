defmodule GameDB.Storage.Disk.FingerprintIndexTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.FingerprintIndex

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-fingerprint-index-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    index =
      FingerprintIndex.new(
        directory,
        bucket_count: 16
      )

    %{
      directory: directory,
      index: index
    }
  end

  test "returns no candidates for an unknown fingerprint", %{
    index: index
  } do
    assert FingerprintIndex.lookup(
             index,
             fingerprint(1)
           ) ==
             {:ok, []}
  end

  test "adds and finds a game id", %{
    index: index
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               10
             )

    assert FingerprintIndex.lookup(
             index,
             fingerprint
           ) ==
             {:ok, [10]}
  end

  test "persists entries across reopening", %{
    directory: directory,
    index: index
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, _index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               10
             )

    reopened =
      FingerprintIndex.new(
        directory,
        bucket_count: 16
      )

    assert FingerprintIndex.lookup(
             reopened,
             fingerprint
           ) ==
             {:ok, [10]}
  end

  test "does not add the same game id twice", %{
    index: index
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               10
             )

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               10
             )

    assert FingerprintIndex.lookup(
             index,
             fingerprint
           ) ==
             {:ok, [10]}
  end

  test "stores multiple game ids for the same fingerprint", %{
    index: index
  } do
    fingerprint =
      fingerprint(1)

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               10
             )

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               fingerprint,
               20
             )

    assert FingerprintIndex.lookup(
             index,
             fingerprint
           ) ==
             {:ok, [10, 20]}
  end

  test "keeps fingerprints in the same bucket separate", %{
    index: index
  } do
    first =
      <<
        1::unsigned-big-32,
        0::size(224)
      >>

    second =
      <<
        17::unsigned-big-32,
        0::size(224)
      >>

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               first,
               10
             )

    assert {:ok, index} =
             FingerprintIndex.add(
               index,
               second,
               20
             )

    assert FingerprintIndex.lookup(
             index,
             first
           ) ==
             {:ok, [10]}

    assert FingerprintIndex.lookup(
             index,
             second
           ) ==
             {:ok, [20]}
  end

  test "rejects fingerprints with the wrong size", %{
    index: index
  } do
    assert FingerprintIndex.lookup(
             index,
             <<1, 2, 3>>
           ) ==
             {:error, :invalid_fingerprint_size}

    assert FingerprintIndex.add(
             index,
             <<1, 2, 3>>,
             1
           ) ==
             {:error, :invalid_fingerprint_size}
  end

  test "propagates a partial bucket entry", %{
    directory: directory,
    index: index
  } do
    fingerprint =
      fingerprint(1)

    path =
      bucket_path(
        directory,
        1
      )

    File.write!(
      path,
      <<1, 2, 3>>
    )

    assert FingerprintIndex.lookup(
             index,
             fingerprint
           ) ==
             {:error, :partial_entry}
  end

  test "recovers a matching partial pending append", %{
    directory: directory,
    index: index
  } do
    fingerprint =
      fingerprint(1)

    entry =
      <<
        fingerprint::binary,
        10::unsigned-big-64
      >>

    path =
      bucket_path(
        directory,
        1
      )

    File.write!(
      path,
      binary_part(
        entry,
        0,
        19
      )
    )

    assert :ok =
             FingerprintIndex.recover_pending_append(
               index,
               fingerprint,
               10
             )

    assert FingerprintIndex.lookup(
             index,
             fingerprint
           ) ==
             {:ok, [10]}
  end

  test "refuses to recover an unrelated partial tail", %{
    directory: directory,
    index: index
  } do
    fingerprint =
      fingerprint(1)

    path =
      bucket_path(
        directory,
        1
      )

    File.write!(
      path,
      <<255, 255, 255>>
    )

    assert FingerprintIndex.recover_pending_append(
             index,
             fingerprint,
             10
           ) ==
             {:error, :unexpected_partial_entry}

    assert File.read!(path) ==
             <<255, 255, 255>>
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end

  defp bucket_path(directory, bucket) do
    filename =
      bucket
      |> Integer.to_string()
      |> String.pad_leading(
        8,
        "0"
      )
      |> then(&"bucket-#{&1}.idx")

    Path.join(
      directory,
      filename
    )
  end
end
