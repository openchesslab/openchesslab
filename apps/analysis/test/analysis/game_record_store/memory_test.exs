defmodule Analysis.GameRecordStore.MemoryTest do
  use ExUnit.Case, async: true

  alias Analysis.GameRecord
  alias Analysis.GameRecordStore.Memory

  setup do
    {:ok, store} =
      Memory.start_link()

    %{store: store}
  end

  test "stores and retrieves a game record", %{
    store: store
  } do
    record =
      GameRecord.new(
        "record-1",
        42,
        %{
          white: "White",
          black: "Black"
        }
      )

    assert :ok =
             Memory.insert(
               store,
               record
             )

    assert Memory.get(
             store,
             "record-1"
           ) ==
             {:ok, record}
  end

  test "does not overwrite an existing record", %{
    store: store
  } do
    original =
      GameRecord.new(
        "record-1",
        42,
        %{
          event: "London"
        }
      )

    other =
      GameRecord.new(
        "record-1",
        43,
        %{
          event: "Paris"
        }
      )

    assert :ok =
             Memory.insert(
               store,
               original
             )

    assert {:error, :already_exists} =
             Memory.insert(
               store,
               other
             )

    assert Memory.get(
             store,
             "record-1"
           ) ==
             {:ok, original}
  end

  test "allows multiple records for the same canonical game", %{
    store: store
  } do
    first =
      GameRecord.new(
        "record-1",
        42,
        %{
          event: "London"
        }
      )

    second =
      GameRecord.new(
        "record-2",
        42,
        %{
          event: "Amsterdam"
        }
      )

    assert :ok =
             Memory.insert(
               store,
               first
             )

    assert :ok =
             Memory.insert(
               store,
               second
             )

    assert Memory.get(
             store,
             "record-1"
           ) ==
             {:ok, first}

    assert Memory.get(
             store,
             "record-2"
           ) ==
             {:ok, second}
  end

  test "returns not_found for an unknown record", %{
    store: store
  } do
    assert Memory.get(
             store,
             "missing"
           ) ==
             :not_found
  end

  test "lists stored game records", %{
    store: store
  } do
    first =
      GameRecord.new(
        "record-1",
        41
      )

    second =
      GameRecord.new(
        "record-2",
        42
      )

    assert :ok =
             Memory.insert(
               store,
               first
             )

    assert :ok =
             Memory.insert(
               store,
               second
             )

    assert MapSet.new(Memory.list(store)) ==
             MapSet.new([
               first,
               second
             ])
  end

  test "lists no records for an empty store", %{
    store: store
  } do
    assert Memory.list(store) == []
  end
end
