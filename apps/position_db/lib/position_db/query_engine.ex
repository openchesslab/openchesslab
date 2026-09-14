defmodule PositionDB.QueryEngine do
  @moduledoc """
  Builds and executes position query plans.
  """

  alias PositionDB.And
  alias PositionDB.Empty
  alias PositionDB.Or
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor

  @spec execute(PropertyIndex.t(), PositionDB.Query.t()) :: MapSet.t()
  def execute(index, query) do
    index
    |> build_executor(query)
    |> collect()
  end

  @spec build_executor(PropertyIndex.t(), PositionDB.Query.t()) :: QueryExecutor.t()
  defp build_executor(index, {:property, property, value}) do
    PropertyIndexScan.new(index, {property, value})
  end

  defp build_executor(index, {:and, queries}) do
    queries
    |> Enum.map(&build_executor(index, &1))
    |> build_and()
  end

  defp build_executor(index, {:or, queries}) do
    queries
    |> Enum.map(&build_executor(index, &1))
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

  @spec collect(QueryExecutor.t()) :: MapSet.t()
  defp collect(executor) do
    executor
    |> collect_ids([])
    |> MapSet.new()
  end

  @spec collect_ids(QueryExecutor.t(), [non_neg_integer()]) :: [non_neg_integer()]
  defp collect_ids(executor, ids) do
    case QueryExecutor.next(executor) do
      {:ok, position_id, executor} ->
        collect_ids(executor, [position_id | ids])

      :done ->
        ids
    end
  end
end
