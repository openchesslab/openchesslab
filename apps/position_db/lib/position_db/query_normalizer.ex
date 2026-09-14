defmodule PositionDB.QueryNormalizer do
  @spec normalize(PositionDB.Query.t()) :: PositionDB.Query.t()
  def normalize(query) do
    do_normalize(query)
  end

  defp do_normalize({:property, _property, _value} = query) do
    query
  end

  defp do_normalize({:not, query}) do
    {:not, do_normalize(query)}
  end

  defp do_normalize({:and, queries}) do
    queries
    |> Enum.flat_map(&normalize_and/1)
    |> Enum.uniq()
    |> normalize_group(:and)
  end

  defp do_normalize({:or, queries}) do
    queries
    |> Enum.flat_map(&normalize_or/1)
    |> Enum.uniq()
    |> normalize_group(:or)
  end

  defp normalize_and(query) do
    case do_normalize(query) do
      {:and, queries} -> queries
      query -> [query]
    end
  end

  defp normalize_or(query) do
    case do_normalize(query) do
      {:or, queries} -> queries
      query -> [query]
    end
  end

  defp normalize_group([query], _operator), do: query

  defp normalize_group(queries, operator) do
    {operator, queries}
  end
end
