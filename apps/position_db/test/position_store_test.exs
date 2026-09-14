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
end
