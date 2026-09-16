defmodule PositionDB.PositionStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore

  defp key(position), do: :erlang.phash2(position)

  test "new position gets an id" do
    store = PositionStore.new(&key/1)

    {store, position_id} = PositionStore.put(store, :position_a)

    assert position_id == 1
    assert PositionStore.get(store, position_id) == {:ok, :position_a}
  end

  test "different positions get different ids" do
    store = PositionStore.new(&key/1)

    {store, id_a} = PositionStore.put(store, :position_a)
    {_store, id_b} = PositionStore.put(store, :position_b)

    assert id_a == 1
    assert id_b == 2
  end

  test "same position gets the same id" do
    store = PositionStore.new(&key/1)

    {store, id_1} = PositionStore.put(store, :position_a)
    {_store, id_2} = PositionStore.put(store, :position_a)

    assert id_1 == id_2
  end

  test "find returns the id of an existing position" do
    store = PositionStore.new(&key/1)

    {store, position_id} = PositionStore.put(store, :position_a)

    assert PositionStore.find(store, :position_a) == {:ok, position_id}
    assert PositionStore.find(store, :position_b) == :not_found
  end

  test "scans position IDs in ascending order" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)
    {store, 3} = PositionStore.put(store, :position_3)

    state = PositionStore.scan(store)

    assert {:ok, 1, state} = PositionStore.scan_next(state)
    assert {:ok, 2, state} = PositionStore.scan_next(state)
    assert {:ok, 3, state} = PositionStore.scan_next(state)
    assert :done = PositionStore.scan_next(state)
  end

  test "scans an empty store" do
    store = PositionStore.new(& &1)

    state = PositionStore.scan(store)

    assert :done = PositionStore.scan_next(state)
  end

  test "returns the number of stored positions" do
    store = PositionStore.new(& &1)

    assert PositionStore.cardinality(store) == 0

    {store, _} = PositionStore.put(store, :position_1)
    {store, _} = PositionStore.put(store, :position_2)

    assert PositionStore.cardinality(store) == 2
  end

  test "counts unique positions" do
    store = PositionStore.new(& &1)

    {store, _} = PositionStore.put(store, :position)
    {store, _} = PositionStore.put(store, :position)

    assert PositionStore.cardinality(store) == 1
  end

  test "deletes a position" do
    store = PositionStore.new(& &1)

    {store, position_id} = PositionStore.put(store, :position)

    store = PositionStore.delete(store, position_id)

    assert PositionStore.get(store, position_id) == :not_found
    assert PositionStore.find(store, :position) == :not_found
  end

  test "deleting a position does not affect other positions" do
    store = PositionStore.new(& &1)

    {store, position_id_1} = PositionStore.put(store, :position_1)
    {store, position_id_2} = PositionStore.put(store, :position_2)

    store = PositionStore.delete(store, position_id_1)

    assert PositionStore.get(store, position_id_1) == :not_found
    assert PositionStore.find(store, :position_1) == :not_found

    assert PositionStore.get(store, position_id_2) == {:ok, :position_2}
    assert PositionStore.find(store, :position_2) == {:ok, position_id_2}
  end

  test "deleting an unknown position ID leaves the store unchanged" do
    store = PositionStore.new(& &1)

    {store, position_id} = PositionStore.put(store, :position)

    store_after_delete = PositionStore.delete(store, 999)

    assert PositionStore.get(store_after_delete, position_id) == {:ok, :position}
    assert PositionStore.find(store_after_delete, :position) == {:ok, position_id}
  end
end
