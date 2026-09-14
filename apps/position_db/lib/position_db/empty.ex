defmodule PositionDB.Empty do
  @moduledoc """
  Execution node that produces no position IDs.
  """

  alias PositionDB.QueryExecutor

  @type t :: %{}

  @spec new() :: QueryExecutor.t()
  def new do
    QueryExecutor.new(__MODULE__, %{})
  end

  @spec next(t()) :: :done
  def next(%{}) do
    :done
  end
end
