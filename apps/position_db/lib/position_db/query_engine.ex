defmodule PositionDB.QueryEngine do
  @moduledoc """
  Builds and executes position query plans.
  """

  alias PositionDB.And
  alias PositionDB.Empty
  alias PositionDB.EquivalenceScan
  alias PositionDB.Not
  alias PositionDB.Or
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor
  alias PositionDB.QueryNormalizer
  alias PositionDB.QueryPlanner
  alias PositionDB.QueryResult
  alias PositionDB.UniverseScan

  @type options :: %{
          optional(:equivalence_index) => PositionDB.EquivalenceIndex.t(),
          optional(:equivalence_function) => (term() -> term()),
          optional(:matcher) => (term(), term() -> boolean())
        }

  @spec execute(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t()
        ) :: QueryResult.t()
  def execute(index, store, query) do
    execute(index, store, query, %{})
  end

  @spec execute(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          options()
        ) :: QueryResult.t()
  def execute(index, store, query, options) do
    normalized_query = QueryNormalizer.normalize(query)

    planned_query =
      QueryPlanner.plan(
        index,
        store,
        normalized_query,
        planner_options(options)
      )

    executor =
      build_executor(
        index,
        store,
        planned_query,
        options
      )

    QueryResult.new(executor)
  end

  @spec build_executor(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          options()
        ) :: QueryExecutor.t()

  defp build_executor(_index, store, true, _options) do
    UniverseScan.new(store)
  end

  defp build_executor(_index, _store, false, _options) do
    Empty.new()
  end

  defp build_executor(
         index,
         _store,
         {:property, property, value},
         _options
       ) do
    PropertyIndexScan.new(index, {property, value})
  end

  defp build_executor(
         _index,
         store,
         {:equivalent, position},
         %{
           equivalence_index: equivalence_index,
           equivalence_function: equivalence_function,
           matcher: matcher
         }
       ) do
    EquivalenceScan.new(
      equivalence_index,
      store,
      equivalence_function,
      matcher,
      position
    )
  end

  defp build_executor(index, store, {:not, query}, options) do
    universe = UniverseScan.new(store)
    child = build_executor(index, store, query, options)

    Not.new(universe, child)
  end

  defp build_executor(index, store, {:and, queries}, options) do
    queries
    |> Enum.map(&build_executor(index, store, &1, options))
    |> build_and()
  end

  defp build_executor(index, store, {:or, queries}, options) do
    queries
    |> Enum.map(&build_executor(index, store, &1, options))
    |> build_or()
  end

  @spec build_and([QueryExecutor.t()]) :: QueryExecutor.t()
  defp build_and([]) do
    Empty.new()
  end

  defp build_and([first | rest]) do
    Enum.reduce(rest, first, &And.new(&2, &1))
  end

  @spec build_or([QueryExecutor.t()]) :: QueryExecutor.t()
  defp build_or([]) do
    Empty.new()
  end

  defp build_or([first | rest]) do
    Enum.reduce(rest, first, &Or.new(&2, &1))
  end

  defp planner_options(options) do
    Map.take(options, [
      :equivalence_index,
      :equivalence_function
    ])
  end
end
