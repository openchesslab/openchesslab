defmodule PositionDB.QueryResult do
  @moduledoc """
  Lazy result of a position query.
  """

  alias PositionDB.QueryExecutor

  @type position_id :: non_neg_integer()

  @type t :: %__MODULE__{
          executor: QueryExecutor.t()
        }

  defstruct [:executor]

  @spec new(QueryExecutor.t()) :: t()
  def new(executor) do
    %__MODULE__{
      executor: executor
    }
  end

  @spec next(t()) ::
          {:ok, position_id(), t()}
          | :done
          | {:error, term()}
  def next(
        %__MODULE__{
          executor: executor
        } = result
      ) do
    case QueryExecutor.next(executor) do
      {
        :ok,
        position_id,
        next_executor
      } ->
        {
          :ok,
          position_id,
          %{
            result
            | executor: next_executor
          }
        }

      :done ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end
end
