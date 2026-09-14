defmodule PositionDB.UniverseScanTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore
  alias PositionDB.QueryExecutor
  alias PositionDB.UniverseScan

  test "scans all position IDs in ascending order" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)
    {store, 3} = PositionStore.put(store, :position_3)

    executor = UniverseScan.new(store)

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert {:ok, 3, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns done for an empty store" do
    store = PositionStore.new(& &1)

    executor = UniverseScan.new(store)

    assert :done = QueryExecutor.next(executor)
  end
end
