defmodule PositionDB.Error do
  @moduledoc """
  Query executor that propagates an existing query-planning error.
  """

  alias PositionDB.QueryExecutor

  @spec new(term()) ::
          QueryExecutor.t()
  def new(reason) do
    QueryExecutor.new(
      __MODULE__,
      reason
    )
  end

  @spec next(term()) ::
          {:error, term()}
  def next(reason) do
    {:error, reason}
  end
end
