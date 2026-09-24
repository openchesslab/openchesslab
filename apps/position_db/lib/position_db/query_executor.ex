defmodule PositionDB.QueryExecutor do
  @moduledoc """
  Runtime representation of a query execution node.
  """

  @type position_id :: non_neg_integer()

  @type t :: %__MODULE__{
          module: module(),
          state: term()
        }

  defstruct [:module, :state]

  @spec new(module(), term()) :: t()
  def new(module, state) do
    %__MODULE__{
      module: module,
      state: state
    }
  end

  @spec next(t()) ::
          {:ok, position_id(), t()}
          | :done
          | {:error, term()}
  def next(%__MODULE__{module: module, state: state} = executor) do
    case module.next(state) do
      {:ok, position_id, next_state} ->
        {:ok, position_id, %{executor | state: next_state}}

      :done ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end
end
