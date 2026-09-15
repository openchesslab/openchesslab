defmodule PositionDB.QueryPlanner do
  alias PositionDB.EquivalenceIndex
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex

  @type cardinality ::
          {:exact, non_neg_integer()}
          | {:upper_bound, non_neg_integer()}

  @type options :: %{
          optional(:equivalence_index) => EquivalenceIndex.t(),
          optional(:equivalence_function) => (term() -> term())
        }

  @spec plan(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t()
        ) :: PositionDB.Query.t()
  def plan(index, store, query) do
    do_plan(index, store, query, %{})
  end

  @spec plan(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          options()
        ) :: PositionDB.Query.t()
  def plan(index, store, query, options) do
    do_plan(index, store, query, options)
  end

  defp do_plan(_index, _store, true, _options), do: true
  defp do_plan(_index, _store, false, _options), do: false

  defp do_plan(
         _index,
         _store,
         {:property, _property, _value} = query,
         _options
       ) do
    query
  end

  defp do_plan(
         _index,
         _store,
         {:equivalent, _position} = query,
         _options
       ) do
    query
  end

  defp do_plan(index, store, {:and, queries}, options) do
    queries
    |> Enum.map(&do_plan(index, store, &1, options))
    |> Enum.sort_by(fn query ->
      cardinality(index, store, query, options)
      |> upper_bound()
    end)
    |> then(&{:and, &1})
  end

  defp do_plan(index, store, {:or, queries}, options) do
    {:or, Enum.map(queries, &do_plan(index, store, &1, options))}
  end

  defp do_plan(index, store, {:not, query}, options) do
    {:not, do_plan(index, store, query, options)}
  end

  defp cardinality(_index, store, true, _options) do
    {:exact, PositionStore.cardinality(store)}
  end

  defp cardinality(_index, _store, false, _options) do
    {:exact, 0}
  end

  defp cardinality(
         index,
         _store,
         {:property, property, value},
         _options
       ) do
    {:exact, PropertyIndex.cardinality(index, {property, value})}
  end

  defp cardinality(
         _index,
         _store,
         {:equivalent, position},
         %{
           equivalence_index: equivalence_index,
           equivalence_function: equivalence_function
         }
       ) do
    key = equivalence_function.(position)

    candidate_count =
      equivalence_index
      |> EquivalenceIndex.lookup(key)
      |> MapSet.size()

    {:upper_bound, candidate_count}
  end

  defp cardinality(
         _index,
         _store,
         {:equivalent, _position},
         _options
       ) do
    raise ArgumentError,
          "equivalence planning requires :equivalence_index and :equivalence_function"
  end

  defp cardinality(index, store, {:and, queries}, options) do
    upper_bound =
      queries
      |> Enum.map(&cardinality(index, store, &1, options))
      |> Enum.map(&upper_bound/1)
      |> Enum.min(fn -> PositionStore.cardinality(store) end)

    {:upper_bound, upper_bound}
  end

  defp cardinality(index, store, {:or, queries}, options) do
    universe = PositionStore.cardinality(store)

    upper_bound =
      queries
      |> Enum.map(&cardinality(index, store, &1, options))
      |> Enum.map(&upper_bound/1)
      |> Enum.sum()
      |> min(universe)

    {:upper_bound, upper_bound}
  end

  defp cardinality(index, store, {:not, query}, options) do
    case cardinality(index, store, query, options) do
      {:exact, value} ->
        {:exact, PositionStore.cardinality(store) - value}

      {:upper_bound, _value} ->
        {:upper_bound, PositionStore.cardinality(store)}
    end
  end

  defp upper_bound({:exact, value}), do: value
  defp upper_bound({:upper_bound, value}), do: value
end
