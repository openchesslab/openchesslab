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
        ) ::
          PositionDB.Query.t()
          | {:error, term()}
  def plan(
        index,
        store,
        query
      ) do
    plan(
      index,
      store,
      query,
      %{}
    )
  end

  @spec plan(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          options()
        ) ::
          PositionDB.Query.t()
          | {:error, term()}
  def plan(
        index,
        store,
        query,
        options
      ) do
    case do_plan(
           index,
           store,
           query,
           options
         ) do
      {:ok, planned} ->
        planned

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_plan(
         _index,
         _store,
         true,
         _options
       ) do
    {:ok, true}
  end

  defp do_plan(
         _index,
         _store,
         false,
         _options
       ) do
    {:ok, false}
  end

  defp do_plan(
         _index,
         _store,
         {:property, _property, _value} = query,
         _options
       ) do
    {:ok, query}
  end

  defp do_plan(
         _index,
         _store,
         {:equivalent, _position} = query,
         _options
       ) do
    {:ok, query}
  end

  defp do_plan(
         index,
         store,
         {:and, queries},
         options
       ) do
    with {:ok, planned} <-
           plan_queries(
             index,
             store,
             queries,
             options
           ),
         {:ok, ordered} <-
           order_by_cardinality(
             index,
             store,
             planned,
             options
           ) do
      {:ok, {:and, ordered}}
    end
  end

  defp do_plan(
         index,
         store,
         {:or, queries},
         options
       ) do
    with {:ok, planned} <-
           plan_queries(
             index,
             store,
             queries,
             options
           ) do
      {:ok, {:or, planned}}
    end
  end

  defp do_plan(
         index,
         store,
         {:not, query},
         options
       ) do
    with {:ok, planned} <-
           do_plan(
             index,
             store,
             query,
             options
           ) do
      {:ok, {:not, planned}}
    end
  end

  defp plan_queries(
         index,
         store,
         queries,
         options
       ) do
    Enum.reduce_while(
      queries,
      {:ok, []},
      fn query, {:ok, planned} ->
        case do_plan(
               index,
               store,
               query,
               options
             ) do
          {:ok, child} ->
            {:cont, {:ok, [child | planned]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, planned} ->
        {:ok, Enum.reverse(planned)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp order_by_cardinality(
         index,
         store,
         queries,
         options
       ) do
    queries
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, []},
      fn {query, original_index}, {:ok, planned} ->
        case cardinality(
               index,
               store,
               query,
               options
             ) do
          {:ok, cardinality} ->
            {:cont,
             {:ok,
              [
                {
                  query,
                  upper_bound(cardinality),
                  original_index
                }
                | planned
              ]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, planned} ->
        ordered =
          planned
          |> Enum.sort_by(fn {
                               _query,
                               count,
                               original_index
                             } ->
            {
              count,
              original_index
            }
          end)
          |> Enum.map(fn {
                           query,
                           _count,
                           _original_index
                         } ->
            query
          end)

        {:ok, ordered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cardinality(
         _index,
         store,
         true,
         _options
       ) do
    {:ok, {:exact, PositionStore.cardinality(store)}}
  end

  defp cardinality(
         _index,
         _store,
         false,
         _options
       ) do
    {:ok, {:exact, 0}}
  end

  defp cardinality(
         index,
         _store,
         {:property, property, value},
         _options
       ) do
    with {:ok, count} <-
           PropertyIndex.cardinality_result(
             index,
             {property, value}
           ) do
      {:ok, {:exact, count}}
    end
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
    key =
      equivalence_function.(position)

    candidate_count =
      equivalence_index
      |> EquivalenceIndex.lookup(key)
      |> MapSet.size()

    {:ok, {:upper_bound, candidate_count}}
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

  defp cardinality(
         index,
         store,
         {:and, queries},
         options
       ) do
    with {:ok, values} <-
           cardinalities(
             index,
             store,
             queries,
             options
           ) do
      upper_bound =
        values
        |> Enum.map(&upper_bound/1)
        |> Enum.min(fn ->
          PositionStore.cardinality(store)
        end)

      {:ok, {:upper_bound, upper_bound}}
    end
  end

  defp cardinality(
         index,
         store,
         {:or, queries},
         options
       ) do
    with {:ok, values} <-
           cardinalities(
             index,
             store,
             queries,
             options
           ) do
      universe =
        PositionStore.cardinality(store)

      upper_bound =
        values
        |> Enum.map(&upper_bound/1)
        |> Enum.sum()
        |> min(universe)

      {:ok, {:upper_bound, upper_bound}}
    end
  end

  defp cardinality(
         index,
         store,
         {:not, query},
         options
       ) do
    with {:ok, value} <-
           cardinality(
             index,
             store,
             query,
             options
           ) do
      case value do
        {:exact, count} ->
          {:ok, {:exact, PositionStore.cardinality(store) - count}}

        {:upper_bound, _count} ->
          {:ok, {:upper_bound, PositionStore.cardinality(store)}}
      end
    end
  end

  defp cardinalities(
         index,
         store,
         queries,
         options
       ) do
    Enum.reduce_while(
      queries,
      {:ok, []},
      fn query, {:ok, values} ->
        case cardinality(
               index,
               store,
               query,
               options
             ) do
          {:ok, value} ->
            {:cont, {:ok, [value | values]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, values} ->
        {:ok, Enum.reverse(values)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upper_bound({:exact, value}),
    do: value

  defp upper_bound({:upper_bound, value}),
    do: value
end
