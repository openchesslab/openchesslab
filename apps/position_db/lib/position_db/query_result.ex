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
end
