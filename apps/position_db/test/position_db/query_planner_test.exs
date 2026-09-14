defmodule PositionDB.QueryPlannerTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryPlanner

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
end
