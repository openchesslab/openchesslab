defmodule GameDB.Storage.Disk.GameOccurrenceIndexTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.GameOccurrenceIndex

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-game-occurrence-index-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, index} =
             GameOccurrenceIndex.create(directory)

    %{
      directory: directory,
      index: index
    }
  end

  test "creates an empty index", %{
    index: index
  } do
    assert GameOccurrenceIndex.cardinality(index) ==
             {:ok, 0}

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             :not_found
  end

  test "stores occurrence spans by game id", %{
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.append(
               index,
               1,
               1,
               3
             )

    assert :ok =
             GameOccurrenceIndex.append(
               index,
               2,
               4,
               2
             )

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {1, 3}}

    assert GameOccurrenceIndex.get(
             index,
             2
           ) ==
             {:ok, {4, 2}}

    assert GameOccurrenceIndex.cardinality(index) ==
             {:ok, 2}
  end

  test "reopens persisted spans", %{
    directory: directory,
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.append(
               index,
               1,
               10,
               4
             )

    assert {:ok, reopened} =
             GameOccurrenceIndex.open(directory)

    assert GameOccurrenceIndex.get(
             reopened,
             1
           ) ==
             {:ok, {10, 4}}
  end

  test "rejects gaps in game ids", %{
    index: index
  } do
    assert GameOccurrenceIndex.append(
             index,
             2,
             1,
             3
           ) ==
             {:error,
              {
                :unexpected_index_size,
                12,
                0
              }}
  end

  test "does not overwrite an existing game span", %{
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.append(
               index,
               1,
               1,
               3
             )

    assert GameOccurrenceIndex.append(
             index,
             1,
             10,
             2
           ) ==
             {:error,
              {
                :unexpected_index_size,
                0,
                12
              }}

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {1, 3}}
  end

  test "detects a partial index entry", %{
    index: index
  } do
    File.write!(
      index.path,
      <<1, 2, 3>>
    )

    assert GameOccurrenceIndex.cardinality(index) ==
             {:error, :partial_entry}
  end

  test "recovers a missing pending entry", %{
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.recover_pending_append(
               index,
               1,
               10,
               4
             )

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {10, 4}}
  end

  test "recovers a matching partial pending entry", %{
    index: index
  } do
    entry =
      <<
        10::unsigned-big-64,
        4::unsigned-big-32
      >>

    File.write!(
      index.path,
      binary_part(
        entry,
        0,
        7
      )
    )

    assert :ok =
             GameOccurrenceIndex.recover_pending_append(
               index,
               1,
               10,
               4
             )

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {10, 4}}
  end

  test "recovery is idempotent for a complete matching entry", %{
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.append(
               index,
               1,
               10,
               4
             )

    assert :ok =
             GameOccurrenceIndex.recover_pending_append(
               index,
               1,
               10,
               4
             )

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {10, 4}}
  end

  test "refuses an unrelated partial pending entry", %{
    index: index
  } do
    File.write!(
      index.path,
      <<255, 255, 255>>
    )

    assert GameOccurrenceIndex.recover_pending_append(
             index,
             1,
             10,
             4
           ) ==
             {:error, :unexpected_partial_entry}

    assert File.read!(index.path) ==
             <<255, 255, 255>>
  end

  test "refuses a different complete entry during recovery", %{
    index: index
  } do
    assert :ok =
             GameOccurrenceIndex.append(
               index,
               1,
               10,
               4
             )

    assert GameOccurrenceIndex.recover_pending_append(
             index,
             1,
             20,
             4
           ) ==
             {:error, :unexpected_entry}

    assert GameOccurrenceIndex.get(
             index,
             1
           ) ==
             {:ok, {10, 4}}
  end
end
