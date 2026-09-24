defimpl Enumerable, for: PositionDB.QueryResult do
  alias PositionDB.QueryExecutionError
  alias PositionDB.QueryExecutor

  def reduce(result, acc, fun) do
    reduce_executor(result.executor, acc, fun)
  end

  def count(_struct), do: {:error, __MODULE__}

  def member?(_struct, _value), do: {:error, __MODULE__}

  def slice(_struct), do: {:error, __MODULE__}

  defp reduce_executor(executor, {:cont, acc}, fun) do
    case QueryExecutor.next(executor) do
      {:ok, position_id, next_executor} ->
        reduce_executor(
          next_executor,
          fun.(position_id, acc),
          fun
        )

      :done ->
        {:done, acc}

      {:error, reason} ->
        raise QueryExecutionError,
          reason: reason
    end
  end

  defp reduce_executor(_executor, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp reduce_executor(executor, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce_executor(executor, &1, fun)}
  end
end
