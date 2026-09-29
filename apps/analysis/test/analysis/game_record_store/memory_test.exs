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

  test "lists records for a canonical game", %{
    store: store
  } do
    first =
      GameRecord.new(
        "record-1",
        42
      )

    second =
      GameRecord.new(
        "record-2",
        42
      )

    other =
      GameRecord.new(
        "record-3",
        43
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

    assert :ok =
             Memory.insert(
               store,
               other
             )

    assert MapSet.new(
             Memory.list_by_game_id(
               store,
               42
             )
           ) ==
             MapSet.new([
               first,
               second
             ])
  end

  test "lists no records for an unknown canonical game", %{
    store: store
  } do
    assert Memory.list_by_game_id(
             store,
             999
           ) == []
  end

  test "pages through records for a canonical game without duplicates or omissions",
       %{
         store: store
       } do
    first =
      GameRecord.new(
        "record-1",
        42
      )

    second =
      GameRecord.new(
        "record-2",
        42
      )

    third =
      GameRecord.new(
        "record-3",
        42
      )

    other =
      GameRecord.new(
        "record-4",
        43
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

    assert :ok =
             Memory.insert(
               store,
               third
             )

    assert :ok =
             Memory.insert(
               store,
               other
             )

    assert {
             :ok,
             first_page,
             cursor
           } =
             Memory.records_page_by_game_id(
               store,
               42,
               2
             )

    assert is_reference(cursor)
    assert length(first_page) == 2

    assert {
             :ok,
             second_page,
             :done
           } =
             Memory.next_records_page(
               store,
               cursor,
               2
             )

    records =
      first_page ++
        second_page

    assert MapSet.new(records) ==
             MapSet.new([
               first,
               second,
               third
             ])

    assert Memory.next_records_page(
             store,
             cursor,
             2
           ) ==
             {:error, :cursor_not_found}
  end

  test "returns an empty page for an unknown canonical game", %{
    store: store
  } do
    assert Memory.records_page_by_game_id(
             store,
             999,
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "does not create a cursor when the first page exhausts the records",
       %{
         store: store
       } do
    first =
      GameRecord.new(
        "record-1",
        42
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

    assert {
             :ok,
             records,
             :done
           } =
             Memory.records_page_by_game_id(
               store,
               42,
               2
             )

    assert MapSet.new(records) ==
             MapSet.new([
               first,
               second
             ])
  end

  test "closes an unfinished record cursor", %{
    store: store
  } do
    first =
      GameRecord.new(
        "record-1",
        42
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

    assert {
             :ok,
             [_record],
             cursor
           } =
             Memory.records_page_by_game_id(
               store,
               42,
               1
             )

    assert :ok =
             Memory.close_record_scan(
               store,
               cursor
             )

    assert Memory.next_records_page(
             store,
             cursor,
             1
           ) ==
             {:error, :cursor_not_found}
  end
end
