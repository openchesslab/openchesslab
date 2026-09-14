defmodule PositionDB.PropertyIndexScan do
  @moduledoc """
  Executes a scan over position IDs matching a property.
  """

  alias PositionDB.PropertyIndex
  alias PositionDB.QueryExecutor

  @type t :: %__MODULE__{
          ids: [non_neg_integer()]
        }

  defstruct ids: []

  @spec new(PropertyIndex.t(), {atom(), term()}) :: QueryExecutor.t()
  def new(index, property) do
    state = %__MODULE__{
      ids:
        index
        |> PropertyIndex.lookup(property)
        |> MapSet.to_list()
        |> Enum.sort()
    }

    QueryExecutor.new(__MODULE__, state)
  end

  @spec next(t()) ::
          {:ok, non_neg_integer(), t()}
          | :done
  def next(%__MODULE__{ids: [position_id | rest]} = state) do
    {:ok, position_id, %{state | ids: rest}}
  end

  def next(%__MODULE__{ids: []}) do
    :done
  end
end
