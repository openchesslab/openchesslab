defmodule PositionDB.QueryPlanner do
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex

  @type cardinality :: {:exact, non_neg_integer()} | {:upper_bound, non_neg_integer()}

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
    |> Enum.sort_by(fn query ->
      cardinality(index, store, query)
      |> upper_bound()
    end)
    |> then(&{:and, &1})
  end

  defp do_plan(index, store, {:or, queries}) do
    {:or, Enum.map(queries, &do_plan(index, store, &1))}
  end

  defp do_plan(index, store, {:not, query}) do
    {:not, do_plan(index, store, query)}
  end

  defp cardinality(_index, store, true) do
    {:exact, PositionStore.cardinality(store)}
  end

  defp cardinality(_index, _store, false) do
    {:exact, 0}
  end

  defp cardinality(index, _store, {:property, property, value}) do
    {:exact, PropertyIndex.cardinality(index, {property, value})}
  end

  defp cardinality(index, store, {:and, queries}) do
    upper_bound =
      queries
      |> Enum.map(&cardinality(index, store, &1))
      |> Enum.map(&upper_bound/1)
      |> Enum.min(fn -> PositionStore.cardinality(store) end)

    {:upper_bound, upper_bound}
  end

  defp cardinality(index, store, {:or, queries}) do
    universe = PositionStore.cardinality(store)

    upper_bound =
      queries
      |> Enum.map(&cardinality(index, store, &1))
      |> Enum.map(&upper_bound/1)
      |> Enum.sum()
      |> min(universe)

    {:upper_bound, upper_bound}
  end

  defp cardinality(index, store, {:not, query}) do
    case cardinality(index, store, query) do
      {:exact, value} ->
        {:exact, PositionStore.cardinality(store) - value}

      {:upper_bound, _value} ->
        {:upper_bound, PositionStore.cardinality(store)}
    end
  end

  defp upper_bound({:exact, value}), do: value
  defp upper_bound({:upper_bound, value}), do: value
end
