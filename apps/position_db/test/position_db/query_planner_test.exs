defmodule PositionDB.QueryPlannerTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryPlanner

  defp store_with_ids(ids) do
    Enum.reduce(ids, PositionStore.new(& &1), fn id, store ->
      {store, _position_id} = PositionStore.put(store, id)
      store
    end)
  end

  describe "plan/3" do
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
        {:and,
         [
           {:property, :open_files, :a},
           {:property, :open_files, :d},
           {:property, :open_files, :e}
         ]}

      assert QueryPlanner.plan(index, store, query) ==
               {:and,
                [
                  {:property, :open_files, :e},
                  {:property, :open_files, :d},
                  {:property, :open_files, :a}
                ]}
    end

    test "preserves OR order" do
      index = PropertyIndex.new()
      store = PositionStore.new(& &1)

      query =
        {:or,
         [
           {:property, :open_files, :a},
           {:property, :open_files, :e},
           {:property, :open_files, :d}
         ]}

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
        {:or,
         [
           {:and,
            [
              {:property, :open_files, :a},
              {:property, :open_files, :e}
            ]},
           {:property, :open_files, :d}
         ]}

      assert QueryPlanner.plan(index, store, query) ==
               {:or,
                [
                  {:and,
                   [
                     {:property, :open_files, :e},
                     {:property, :open_files, :a}
                   ]},
                  {:property, :open_files, :d}
                ]}
    end

    test "plans NOT recursively" do
      index =
        PropertyIndex.new()
        |> PropertyIndex.add({:open_files, :a}, 1)
        |> PropertyIndex.add({:open_files, :e}, 1)
        |> PropertyIndex.add({:open_files, :e}, 2)

      store = PositionStore.new(& &1)

      query =
        {:not,
         {:and,
          [
            {:property, :open_files, :a},
            {:property, :open_files, :e}
          ]}}

      assert QueryPlanner.plan(index, store, query) ==
               {:not,
                {:and,
                 [
                   {:property, :open_files, :a},
                   {:property, :open_files, :e}
                 ]}}
    end

    test "leaves property queries unchanged" do
      index = PropertyIndex.new()
      store = PositionStore.new(& &1)

      query = {:property, :open_files, :e}

      assert QueryPlanner.plan(index, store, query) == query
    end
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
      {:and,
       [
         {:or,
          [
            {:property, :open_files, :e},
            {:property, :open_files, :d}
          ]},
         {:property, :open_files, :c}
       ]}

    assert QueryPlanner.plan(index, store, query) ==
             {:and,
              [
                {:or,
                 [
                   {:property, :open_files, :e},
                   {:property, :open_files, :d}
                 ]},
                {:property, :open_files, :c}
              ]}
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
      {:and,
       [
         {:and,
          [
            {:property, :open_files, :e},
            {:property, :open_files, :d}
          ]},
         {:property, :open_files, :c}
       ]}

    assert QueryPlanner.plan(index, store, query) ==
             {:and,
              [
                {:and,
                 [
                   {:property, :open_files, :e},
                   {:property, :open_files, :d}
                 ]},
                {:property, :open_files, :c}
              ]}
  end
end
