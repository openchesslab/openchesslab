defmodule PositionDB.QueryEngineTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore
  alias PositionDB.QueryEngine
  alias PositionDB.PropertyIndex

  test "property query returns matching positions" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    query = {:property, :open_files, :e}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([1, 2])
  end

  test "and query returns intersection" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([2])
  end

  test "and query with multiple properties" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)
      |> PropertyIndex.add({:open_files, :d}, 4)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d},
         {:property, :open_files, :c}
       ]}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([3])
  end

  test "or query returns union" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    query =
      {:or,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([1, 2, 3])
  end

  test "not query returns positions outside the child result" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)
    {store, 3} = PositionStore.put(store, :position_3)
    {store, 4} = PositionStore.put(store, :position_4)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:selected, true}, 2)
      |> PropertyIndex.add({:selected, true}, 4)

    query =
      {:not, {:property, :selected, true}}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([1, 3])
  end

  test "not can be combined with and" do
    store = PositionStore.new(& &1)

    {store, 1} = PositionStore.put(store, :position_1)
    {store, 2} = PositionStore.put(store, :position_2)
    {store, 3} = PositionStore.put(store, :position_3)
    {store, 4} = PositionStore.put(store, :position_4)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:a, true}, 1)
      |> PropertyIndex.add({:a, true}, 2)
      |> PropertyIndex.add({:b, true}, 2)
      |> PropertyIndex.add({:b, true}, 3)

    query =
      {:not,
       {:and,
        [
          {:property, :a, true},
          {:property, :b, true}
        ]}}

    assert QueryEngine.execute(index, store, query) ==
             MapSet.new([1, 3, 4])
  end
end
