defmodule PositionDB.QueryEngine do
  @moduledoc """
  Builds and executes position query plans.
  """

  alias PositionDB.QueryResult
  alias PositionDB.And
  alias PositionDB.Empty
  alias PositionDB.Not
  alias PositionDB.Or
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor
  alias PositionDB.UniverseScan

  @spec execute(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t()
        ) :: QueryResult.t()
  def execute(index, store, query) do
    index
    |> build_executor(store, query)
    |> QueryResult.new()
  end

  @spec build_executor(
          PropertyIndex.t(),
          PositionStore.t(),
          PositionDB.Query.t()
        ) :: QueryExecutor.t()
  defp build_executor(index, _store, {:property, property, value}) do
    PropertyIndexScan.new(index, {property, value})
  end

  defp build_executor(index, store, {:not, query}) do
    universe = UniverseScan.new(store)
    child = build_executor(index, store, query)

    Not.new(universe, child)
  end

  defp build_executor(index, store, {:and, queries}) do
    queries
    |> Enum.map(&build_executor(index, store, &1))
    |> build_and()
  end

  defp build_executor(index, store, {:or, queries}) do
    queries
    |> Enum.map(&build_executor(index, store, &1))
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
