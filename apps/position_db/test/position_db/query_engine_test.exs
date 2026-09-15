defmodule PositionDB.QueryEngineTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryEngine

  test "property query returns matching positions" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    query = {:property, :open_files, :e}

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1, 2]
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

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [2]
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

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1, 2, 3]
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

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [3]
  end

  test "not query returns positions outside the child result" do
    {store, _} = PositionStore.put(PositionStore.new(& &1), :position_1)
    {store, _} = PositionStore.put(store, :position_2)
    {store, _} = PositionStore.put(store, :position_3)
    {store, _} = PositionStore.put(store, :position_4)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:selected, true}, 2)
      |> PropertyIndex.add({:selected, true}, 4)

    query =
      {:not, {:property, :selected, true}}

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1, 3]
  end

  test "not can be combined with and" do
    {store, _} = PositionStore.put(PositionStore.new(& &1), :position_1)
    {store, _} = PositionStore.put(store, :position_2)
    {store, _} = PositionStore.put(store, :position_3)
    {store, _} = PositionStore.put(store, :position_4)

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

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1, 3, 4]
  end

  test "plans AND queries before execution" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :a}, 1)
      |> PropertyIndex.add({:open_files, :a}, 2)
      |> PropertyIndex.add({:open_files, :e}, 1)

    store = PositionStore.new(& &1)

    query =
      {:and,
       [
         {:property, :open_files, :a},
         {:property, :open_files, :e}
       ]}

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1]
  end

  test "normalizes queries before execution" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :a}, 1)
      |> PropertyIndex.add({:open_files, :a}, 2)
      |> PropertyIndex.add({:open_files, :b}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :e}, 1)

    store = PositionStore.new(& &1)

    query =
      {:and,
       [
         {:property, :open_files, :a},
         {:and,
          [
            {:property, :open_files, :b},
            {:property, :open_files, :d}
          ]}
       ]}

    result = QueryEngine.execute(index, store, query)

    assert Enum.to_list(result) == [1]
  end

  test "executes true as the universe" do
    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, :position_1)
    {store, id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result = QueryEngine.execute(index, store, true)

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "executes false as an empty result" do
    store = PositionStore.new(& &1)

    {store, _id_1} = PositionStore.put(store, :position_1)
    {store, _id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result = QueryEngine.execute(index, store, false)

    assert Enum.to_list(result) == []
  end

  test "executes an empty AND as the universe" do
    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, :position_1)
    {store, id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result = QueryEngine.execute(index, store, {:and, []})

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "executes an empty OR as an empty result" do
    store = PositionStore.new(& &1)

    {store, _id_1} = PositionStore.put(store, :position_1)
    {store, _id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result = QueryEngine.execute(index, store, {:or, []})

    assert Enum.to_list(result) == []
  end
end
