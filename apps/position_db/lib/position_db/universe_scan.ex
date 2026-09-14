defmodule PositionDB.UniverseScan do
  @moduledoc """
  Executes a scan over all active position IDs.
  """

  alias PositionDB.PositionStore
  alias PositionDB.QueryExecutor

  @type t :: %__MODULE__{
          scan: PositionStore.scan_state()
        }

  defstruct [:scan]

  @spec new(PositionStore.t()) :: QueryExecutor.t()
  def new(store) do
    QueryExecutor.new(
      __MODULE__,
      %__MODULE__{
        scan: PositionStore.scan(store)
      }
    )
  end

  @spec next(t()) ::
          {:ok, non_neg_integer(), t()}
          | :done
  def next(%__MODULE__{scan: scan} = state) do
    case PositionStore.scan_next(scan) do
      {:ok, position_id, next_scan} ->
        {:ok, position_id, %{state | scan: next_scan}}

      :done ->
        :done
    end
  end
end
