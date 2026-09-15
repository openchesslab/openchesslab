defmodule PositionDB.QueryEngineTest do
  use ExUnit.Case, async: true

  alias PositionDB.EquivalenceContext
  alias PositionDB.EquivalenceIndex
  alias PositionDB.Query
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryEngine

  defp store_with_ids(ids) do
    Enum.reduce(ids, PositionStore.new(& &1), fn id, store ->
      {store, _position_id} = PositionStore.put(store, id)
      store
    end)
  end

  defp equivalence_context do
    EquivalenceContext.new(& &1, &(&1 == &2))
  end

  test "property query returns matching positions" do
    store = PositionStore.new(& &1)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    query = Query.property(:open_files, :e)

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

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
      Query.all([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

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
      Query.any([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

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
      Query.all([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d),
        Query.property(:open_files, :c)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [3]
  end

  test "not query returns positions outside the child result" do
    {store, _} =
      PositionStore.put(
        PositionStore.new(& &1),
        :position_1
      )

    {store, _} = PositionStore.put(store, :position_2)
    {store, _} = PositionStore.put(store, :position_3)
    {store, _} = PositionStore.put(store, :position_4)

    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:selected, true}, 2)
      |> PropertyIndex.add({:selected, true}, 4)

    query = Query.negate(Query.property(:selected, true))

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1, 3]
  end

  test "not can be combined with and" do
    {store, _} =
      PositionStore.put(
        PositionStore.new(& &1),
        :position_1
      )

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
      Query.negate(
        Query.all([
          Query.property(:a, true),
          Query.property(:b, true)
        ])
      )

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

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
      Query.all([
        Query.property(:open_files, :a),
        Query.property(:open_files, :e)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

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
      Query.all([
        Query.property(:open_files, :a),
        Query.all([
          Query.property(:open_files, :b),
          Query.property(:open_files, :d)
        ])
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1]
  end

  test "executes true as the universe" do
    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, :position_1)
    {store, id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result =
      QueryEngine.execute(
        index,
        store,
        Query.match_all(),
        equivalence_context()
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "executes false as an empty result" do
    store = PositionStore.new(& &1)

    {store, _id_1} = PositionStore.put(store, :position_1)
    {store, _id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result =
      QueryEngine.execute(
        index,
        store,
        Query.match_none(),
        equivalence_context()
      )

    assert Enum.to_list(result) == []
  end

  test "executes an empty AND as the universe" do
    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, :position_1)
    {store, id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result =
      QueryEngine.execute(
        index,
        store,
        Query.all([]),
        equivalence_context()
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "executes an empty OR as an empty result" do
    store = PositionStore.new(& &1)

    {store, _id_1} = PositionStore.put(store, :position_1)
    {store, _id_2} = PositionStore.put(store, :position_2)

    index = PropertyIndex.new()

    result =
      QueryEngine.execute(
        index,
        store,
        Query.any([]),
        equivalence_context()
      )

    assert Enum.to_list(result) == []
  end

  test "executes AND query using planner-selected order" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = PositionStore.new(& &1)

    {store, _id_1} = PositionStore.put(store, :position_1)
    {store, _id_2} = PositionStore.put(store, :position_2)
    {store, _id_3} = PositionStore.put(store, :position_3)
    {store, _id_4} = PositionStore.put(store, :position_4)

    query =
      Query.all([
        Query.property(:open_files, :c),
        Query.property(:open_files, :d),
        Query.property(:open_files, :e)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1]
  end

  test "executes OR query through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    store = store_with_ids([1, 2, 3, 4])

    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1, 2, 3]
  end

  test "executes NOT query through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 4)

    store = store_with_ids([1, 2, 3, 4])

    query = Query.negate(Query.property(:open_files, :e))

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1, 3]
  end

  test "executes AND with NOT through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    query =
      Query.all([
        Query.property(:open_files, :c),
        Query.negate(Query.property(:open_files, :e))
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1, 3, 4]
  end

  test "executes AND with true through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)

    store = store_with_ids([1, 2, 3])

    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.match_all()
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [2]
  end

  test "executes OR with false through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)

    store = store_with_ids([1, 2, 3])

    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.match_none()
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [2]
  end

  test "executes AND with complementary queries through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)

    store = store_with_ids([1, 2, 3])

    property = Query.property(:open_files, :e)

    query =
      Query.all([
        property,
        Query.negate(property)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == []
  end

  test "executes OR with complementary queries through the full pipeline" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 2)

    store = store_with_ids([1, 2, 3])

    property = Query.property(:open_files, :e)

    query =
      Query.any([
        property,
        Query.negate(property)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [1, 2, 3]
  end

  test "executes equivalent query through the full pipeline" do
    position = :position
    swapped_position = :swapped_position
    unrelated_position = :unrelated_position

    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, position)
    {store, id_2} = PositionStore.put(store, swapped_position)
    {store, id_3} = PositionStore.put(store, unrelated_position)

    equivalence_index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:equivalent, id_1)
      |> EquivalenceIndex.add(:equivalent, id_2)
      |> EquivalenceIndex.add(:unrelated, id_3)

    matcher = fn
      :position, :position -> true
      :position, :swapped_position -> true
      _, _ -> false
    end

    equivalence =
      %EquivalenceContext{
        index: equivalence_index,
        key_function: fn
          :position -> :equivalent
          :swapped_position -> :equivalent
          :unrelated_position -> :unrelated
        end,
        matcher: matcher
      }

    query = Query.equivalent(position)

    result =
      QueryEngine.execute(
        PropertyIndex.new(),
        store,
        query,
        equivalence
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "executes AND conditions in planned cardinality order" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :large}, 1)
      |> PropertyIndex.add({:open_files, :large}, 2)
      |> PropertyIndex.add({:open_files, :large}, 3)
      |> PropertyIndex.add({:open_files, :large}, 4)
      |> PropertyIndex.add({:open_files, :small}, 2)
      |> PropertyIndex.add({:open_files, :small}, 4)

    store = store_with_ids([1, 2, 3, 4])

    query =
      Query.all([
        Query.property(:open_files, :large),
        Query.property(:open_files, :small)
      ])

    result =
      QueryEngine.execute(
        index,
        store,
        query,
        equivalence_context()
      )

    assert Enum.to_list(result) == [2, 4]
  end
end
