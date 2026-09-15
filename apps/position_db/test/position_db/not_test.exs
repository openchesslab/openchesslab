defmodule PositionDB.NotTest do
  use ExUnit.Case, async: true

  alias PositionDB.Not
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor
  alias PositionDB.UniverseScan

  test "returns universe IDs not present in child" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)
    {store, 3} = PositionStore.put(store, :position_3)
    {store, 4} = PositionStore.put(store, :position_4)
    {store, 5} = PositionStore.put(store, :position_5)
    {store, 6} = PositionStore.put(store, :position_6)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:selected, true}, 2)
      |> PropertyIndex.add({:selected, true}, 4)

    universe = UniverseScan.new(store)
    child = PropertyIndexScan.new(index, {:selected, true})

    executor = Not.new(universe, child)

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 3, executor} = QueryExecutor.next(executor)
    assert {:ok, 5, executor} = QueryExecutor.next(executor)
    assert {:ok, 6, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns all universe IDs when child is empty" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    universe = UniverseScan.new(store)
    child = PropertyIndexScan.new(index, {:selected, true})

    executor = Not.new(universe, child)

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns no IDs when child contains the entire universe" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:selected, true}, 1)
      |> PropertyIndex.add({:selected, true}, 2)

    universe = UniverseScan.new(store)
    child = PropertyIndexScan.new(index, {:selected, true})

    executor = Not.new(universe, child)

    assert :done = QueryExecutor.next(executor)
  end

  test "does not evaluate the child when the universe is empty" do
    universe =
      QueryExecutor.new(
        TrackingExecutor,
        {self(), :universe, :done}
      )

    child =
      QueryExecutor.new(
        TrackingExecutor,
        {self(), :child, {:ok, 1, :next}}
      )

    executor = Not.new(universe, child)

    assert QueryExecutor.next(executor) == :done
    assert_receive {:next_called, :universe}
    refute_receive {:next_called, :child}
  end
end
