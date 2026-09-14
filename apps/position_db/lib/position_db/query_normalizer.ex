defmodule PositionDB.QueryNormalizer do
  @spec normalize(PositionDB.Query.t()) :: PositionDB.Query.t()
  def normalize(query) do
    do_normalize(query)
  end

  defp do_normalize(true), do: true
  defp do_normalize(false), do: false

  defp do_normalize({:property, _property, _value} = query) do
    query
  end

  defp do_normalize({:not, query}) do
    query
    |> do_normalize()
    |> normalize_not()
  end

  defp do_normalize({:and, queries}) do
    queries
    |> Enum.flat_map(&normalize_and/1)
    |> Enum.uniq()
    |> normalize_and_result()
  end

  defp do_normalize({:or, queries}) do
    queries
    |> Enum.flat_map(&normalize_or/1)
    |> Enum.uniq()
    |> normalize_or_result()
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

  defp normalize_and_result(queries) do
    cond do
      false in queries ->
        false

      true ->
        queries
        |> Enum.reject(&(&1 == true))
        |> collapse_group(:and, true)
    end
  end

  defp normalize_or_result(queries) do
    cond do
      true in queries ->
        true

      true ->
        queries
        |> Enum.reject(&(&1 == false))
        |> collapse_group(:or, false)
    end
  end

  defp normalize_not(true), do: false
  defp normalize_not(false), do: true
  defp normalize_not({:not, query}), do: query
  defp normalize_not(query), do: {:not, query}

  defp collapse_group([], _operator, identity), do: identity
  defp collapse_group([query], _operator, _identity), do: query
  defp collapse_group(queries, operator, _identity), do: {operator, queries}
end
