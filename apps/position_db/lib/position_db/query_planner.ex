defmodule PositionDB.QueryPlanner do
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex

  @spec plan(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t()
        ) :: PositionDB.Query.t()
  def plan(index, store, query) do
    do_plan(index, store, query)
  end

  defp do_plan(_index, _store, true), do: true
  defp do_plan(_index, _store, false), do: false

  defp do_plan(_index, _store, {:property, _property, _value} = query) do
    query
  end

  defp do_plan(index, store, {:and, queries}) do
    queries
    |> Enum.map(&do_plan(index, store, &1))
    |> Enum.sort_by(&cardinality(index, store, &1))
    |> then(&{:and, &1})
  end

  defp do_plan(index, store, {:or, queries}) do
    {:or, Enum.map(queries, &do_plan(index, store, &1))}
  end

  defp do_plan(index, store, {:not, query}) do
    {:not, do_plan(index, store, query)}
  end

  defp cardinality(index, _store, {:property, property, value}) do
    PropertyIndex.cardinality(index, {property, value})
  end

  defp cardinality(_index, store, _query) do
    PositionStore.cardinality(store)
  end
end
