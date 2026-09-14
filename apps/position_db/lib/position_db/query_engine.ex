defmodule PositionDB.QueryEngine do
  @moduledoc """
  Executes position queries against a property index.
  """

  alias PositionDB.PropertyIndex

  @spec execute(PropertyIndex.t(), PositionDB.Query.t()) :: MapSet.t()
  def execute(index, query) do
    execute_query(index, query)
  end

  defp execute_query(index, {:property, property, value}) do
    PropertyIndex.lookup(index, {property, value})
  end

  defp execute_query(index, {:and, queries}) do
    queries
    |> Enum.map(&execute_query(index, &1))
    |> intersect_all()
  end

  defp execute_query(index, {:or, queries}) do
    queries
    |> Enum.map(&execute_query(index, &1))
    |> union_all()
  end

  defp intersect_all([]), do: MapSet.new()

  defp intersect_all([first | rest]) do
    Enum.reduce(rest, first, &MapSet.intersection(&2, &1))
  end

  defp union_all(sets) do
    Enum.reduce(sets, MapSet.new(), &MapSet.union(&2, &1))
  end
end
