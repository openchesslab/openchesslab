defmodule PositionDB.QueryPlannerTest do
  use ExUnit.Case, async: true

  alias PositionDB.Query
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryPlanner

  defp store_with_ids(ids) do
    Enum.reduce(ids, PositionStore.new(& &1), fn id, store ->
      {store, _position_id} = PositionStore.put(store, id)
      store
    end)
  end

  test "orders AND conditions by ascending cardinality" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :a}, 1)
      |> PropertyIndex.add({:open_files, :a}, 2)
      |> PropertyIndex.add({:open_files, :a}, 3)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :e}, 1)

    store = PositionStore.new(& &1)

    query =
      Query.all([
        Query.property(:open_files, :a),
        Query.property(:open_files, :d),
        Query.property(:open_files, :e)
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.all([
               Query.property(:open_files, :e),
               Query.property(:open_files, :d),
               Query.property(:open_files, :a)
             ])
  end

  test "preserves OR order" do
    index = PropertyIndex.new()
    store = PositionStore.new(& &1)

    query =
      Query.any([
        Query.property(:open_files, :a),
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    assert QueryPlanner.plan(index, store, query) == query
  end

  test "plans nested AND expressions recursively" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :a}, 1)
      |> PropertyIndex.add({:open_files, :a}, 2)
      |> PropertyIndex.add({:open_files, :e}, 1)

    store = PositionStore.new(& &1)

    query =
      Query.any([
        Query.all([
          Query.property(:open_files, :a),
          Query.property(:open_files, :e)
        ]),
        Query.property(:open_files, :d)
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.any([
               Query.all([
                 Query.property(:open_files, :e),
                 Query.property(:open_files, :a)
               ]),
               Query.property(:open_files, :d)
             ])
  end

  test "plans NOT recursively" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :a}, 1)
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    store = PositionStore.new(& &1)

    query =
      Query.negate(
        Query.all([
          Query.property(:open_files, :a),
          Query.property(:open_files, :e)
        ])
      )

    assert QueryPlanner.plan(index, store, query) ==
             Query.negate(
               Query.all([
                 Query.property(:open_files, :a),
                 Query.property(:open_files, :e)
               ])
             )
  end

  test "leaves property queries unchanged" do
    index = PropertyIndex.new()
    store = PositionStore.new(& &1)

    query = Query.property(:open_files, :e)

    assert QueryPlanner.plan(index, store, query) == query
  end

  test "leaves equivalent queries unchanged" do
    position = :position
    query = Query.equivalent(position)

    index = PropertyIndex.new()
    store = PositionStore.new(& &1)

    assert QueryPlanner.plan(index, store, query) == query
  end

  test "leaves true unchanged" do
    index = PropertyIndex.new()
    store = PositionStore.new(& &1)

    assert QueryPlanner.plan(index, store, true) == true
  end

  test "leaves false unchanged" do
    index = PropertyIndex.new()
    store = PositionStore.new(& &1)

    assert QueryPlanner.plan(index, store, false) == false
  end

  test "orders AND using cardinality of a nested OR" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    query =
      Query.all([
        Query.any([
          Query.property(:open_files, :e),
          Query.property(:open_files, :d)
        ]),
        Query.property(:open_files, :c)
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.all([
               Query.any([
                 Query.property(:open_files, :e),
                 Query.property(:open_files, :d)
               ]),
               Query.property(:open_files, :c)
             ])
  end

  test "orders AND using cardinality of a nested AND" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    query =
      Query.all([
        Query.all([
          Query.property(:open_files, :e),
          Query.property(:open_files, :d)
        ]),
        Query.property(:open_files, :c)
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.all([
               Query.all([
                 Query.property(:open_files, :e),
                 Query.property(:open_files, :d)
               ]),
               Query.property(:open_files, :c)
             ])
  end

  test "orders AND by exact cardinality of NOT" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    # universe = 4
    # e = 1        => NOT e = 3
    # c = 4
    #
    # Therefore NOT e must be planned before c.
    query =
      Query.all([
        Query.property(:open_files, :c),
        Query.negate(Query.property(:open_files, :e))
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.all([
               Query.negate(Query.property(:open_files, :e)),
               Query.property(:open_files, :c)
             ])
  end

  test "orders NOT of nested AND conservatively" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    # universe = 4
    # e AND d has at most 1 position
    # NOT (e AND d) is therefore conservatively estimated at 4
    # c has exactly 4 positions
    #
    # Both have the same upper bound, so the original order is preserved.
    query =
      Query.all([
        Query.negate(
          Query.all([
            Query.property(:open_files, :e),
            Query.property(:open_files, :d)
          ])
        ),
        Query.property(:open_files, :c)
      ])

    assert QueryPlanner.plan(index, store, query) == query
  end

  test "orders NOT of nested OR conservatively" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    # universe = 4
    # e OR d has an upper bound of 3
    # NOT (e OR d) is conservatively estimated at 4
    # c has exactly 4 positions
    #
    # Both have the same upper bound, so the original order is preserved.

    query =
      Query.all([
        Query.negate(
          Query.any([
            Query.property(:open_files, :e),
            Query.property(:open_files, :d)
          ])
        ),
        Query.property(:open_files, :c)
      ])

    assert QueryPlanner.plan(index, store, query) == query
  end

  test "orders AND using exact cardinality of double NOT" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :c}, 1)
      |> PropertyIndex.add({:open_files, :c}, 2)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    store = store_with_ids([1, 2, 3, 4])

    # universe = 4
    # e = 1
    # NOT e = 3
    # NOT NOT e = 1
    # c = 4
    #
    # Therefore NOT NOT e must be planned before c.
    query =
      Query.all([
        Query.property(:open_files, :c),
        Query.negate(Query.negate(Query.property(:open_files, :e)))
      ])

    assert QueryPlanner.plan(index, store, query) ==
             Query.all([
               Query.negate(Query.negate(Query.property(:open_files, :e))),
               Query.property(:open_files, :c)
             ])
  end

  test "orders equivalent queries by candidate cardinality" do
    store = PositionStore.new(& &1)

    {store, id_1} = PositionStore.put(store, :candidate_1)
    {store, id_2} = PositionStore.put(store, :candidate_2)

    equivalence_index =
      PositionDB.EquivalenceIndex.new()
      |> PositionDB.EquivalenceIndex.add(:small, id_1)
      |> PositionDB.EquivalenceIndex.add(:large, id_1)
      |> PositionDB.EquivalenceIndex.add(:large, id_2)

    query =
      Query.all([
        Query.equivalent(:large),
        Query.equivalent(:small)
      ])

    planned =
      QueryPlanner.plan(
        PropertyIndex.new(),
        store,
        query,
        %{
          equivalence_index: equivalence_index,
          equivalence_function: fn position -> position end
        }
      )

    assert planned ==
             Query.all([
               Query.equivalent(:small),
               Query.equivalent(:large)
             ])
  end
end
