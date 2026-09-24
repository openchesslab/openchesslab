defmodule PositionDB.QueryExecutionError do
  @moduledoc """
  Raised when lazy query execution encounters a storage error.
  """

  defexception [:reason]

  def message(%__MODULE__{
        reason: reason
      }) do
    "query execution failed: #{inspect(reason)}"
  end
end
