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

    {:ok, store, 1} = PositionStore.put(store, :position_1)
    {:ok, store, 2} = PositionStore.put(store, :position_2)
    {:ok, store, 3} = PositionStore.put(store, :position_3)
    {:ok, store, 4} = PositionStore.put(store, :position_4)
    {:ok, store, 5} = PositionStore.put(store, :position_5)
    {:ok, store, 6} = PositionStore.put(store, :position_6)

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

    {:ok, store, 1} = PositionStore.put(store, :position_1)
    {:ok, store, 2} = PositionStore.put(store, :position_2)

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

    {:ok, store, 1} = PositionStore.put(store, :position_1)
    {:ok, store, 2} = PositionStore.put(store, :position_2)

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

  test "equal cardinality does not imply equal execution cost" do
    {:ok, counter} =
      Agent.start_link(fn ->
        %{
          property: 0,
          universe: 0,
          child: 0
        }
      end)

    property =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :property, counter, [1000]}
      )

    universe =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :universe, counter, Enum.to_list(1..1000)}
      )

    child =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :child, counter, Enum.to_list(1..999)}
      )

    not_executor = Not.new(universe, child)

    assert {:ok, 1000, _} = QueryExecutor.next(property)
    assert {:ok, 1000, _} = QueryExecutor.next(not_executor)

    assert Agent.get(counter, & &1) == %{
             property: 1,
             universe: 1000,
             child: 999
           }
  end

  test "propagates a universe error without evaluating the child" do
    universe =
      QueryExecutor.new(
        TrackingExecutor,
        {
          self(),
          :universe,
          {:error, :disk_failure}
        }
      )

    child =
      QueryExecutor.new(
        TrackingExecutor,
        {
          self(),
          :child,
          {:ok, 1, :next}
        }
      )

    executor =
      Not.new(
        universe,
        child
      )

    assert QueryExecutor.next(executor) ==
             {:error, :disk_failure}

    assert_receive {:next_called, :universe}
    refute_receive {:next_called, :child}
  end
end
