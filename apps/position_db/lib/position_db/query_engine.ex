defmodule PositionDB.QueryEngine do
  @moduledoc """
  Builds and executes position query plans.
  """

  alias PositionDB.And
  alias PositionDB.Empty
  alias PositionDB.EquivalenceContext
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

  @spec execute(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          EquivalenceContext.t()
        ) :: QueryResult.t()
  def execute(index, store, query, equivalence) do
    normalized_query =
      QueryNormalizer.normalize(query)

    planned_query =
      QueryPlanner.plan(
        index,
        store,
        normalized_query,
        %{
          equivalence_index: equivalence.index,
          equivalence_function: equivalence.key_function
        }
      )

    executor =
      build_executor(
        index,
        store,
        planned_query,
        equivalence
      )

    QueryResult.new(executor)
  end

  @spec build_executor(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t(),
          EquivalenceContext.t()
        ) :: QueryExecutor.t()

  defp build_executor(_index, store, true, _equivalence) do
    UniverseScan.new(store)
  end

  defp build_executor(_index, _store, false, _equivalence) do
    Empty.new()
  end

  defp build_executor(
         index,
         _store,
         {:property, property, value},
         _equivalence
       ) do
    PropertyIndexScan.new(
      index,
      {property, value}
    )
  end

  defp build_executor(
         _index,
         store,
         {:equivalent, position},
         equivalence
       ) do
    EquivalenceScan.new(
      equivalence.index,
      store,
      equivalence.key_function,
      equivalence.matcher,
      position
    )
  end

  defp build_executor(
         index,
         store,
         {:not, query},
         equivalence
       ) do
    universe = UniverseScan.new(store)

    child =
      build_executor(
        index,
        store,
        query,
        equivalence
      )

    Not.new(universe, child)
  end

  defp build_executor(
         index,
         store,
         {:and, queries},
         equivalence
       ) do
    queries
    |> Enum.map(
      &build_executor(
        index,
        store,
        &1,
        equivalence
      )
    )
    |> build_and()
  end

  defp build_executor(
         index,
         store,
         {:or, queries},
         equivalence
       ) do
    queries
    |> Enum.map(
      &build_executor(
        index,
        store,
        &1,
        equivalence
      )
    )
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
end
