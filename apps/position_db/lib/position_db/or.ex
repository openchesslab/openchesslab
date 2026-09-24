defmodule PositionDB.Or do
  @moduledoc """
  Executes the union of two sorted query executors.
  """

  alias PositionDB.QueryExecutor

  @type position_id :: non_neg_integer()

  @type child ::
          QueryExecutor.t()
          | :done
          | {:error, term()}

  @type t :: %__MODULE__{
          left: child(),
          right: child(),
          left_id: position_id() | nil,
          right_id: position_id() | nil
        }

  defstruct [
    :left,
    :right,
    :left_id,
    :right_id
  ]

  @spec new(QueryExecutor.t(), QueryExecutor.t()) :: QueryExecutor.t()
  def new(left, right) do
    QueryExecutor.new(
      __MODULE__,
      %__MODULE__{
        left: left,
        right: right
      }
    )
  end

  @spec next(t()) ::
          {:ok, position_id(), t()}
          | :done
  def next(%__MODULE__{} = state) do
    state
    |> load_left()
    |> maybe_load_right()
    |> find_next()
  end

  defp load_left(%__MODULE__{left: :done} = state) do
    state
  end

  defp load_left(
         %__MODULE__{
           left: {:error, _reason}
         } = state
       ) do
    state
  end

  defp load_left(%__MODULE__{left_id: nil, left: left} = state) do
    case QueryExecutor.next(left) do
      {:ok, position_id, next_left} ->
        %{state | left: next_left, left_id: position_id}

      :done ->
        %{state | left: :done}

      {:error, reason} ->
        %{state | left: {:error, reason}}
    end
  end

  defp load_left(state), do: state

  defp maybe_load_right(
         %__MODULE__{
           left: {:error, _reason}
         } = state
       ) do
    state
  end

  defp maybe_load_right(state) do
    load_right(state)
  end

  defp load_right(%__MODULE__{right: :done} = state) do
    state
  end

  defp load_right(
         %__MODULE__{
           right: {:error, _reason}
         } = state
       ) do
    state
  end

  defp load_right(%__MODULE__{right_id: nil, right: right} = state) do
    case QueryExecutor.next(right) do
      {:ok, position_id, next_right} ->
        %{state | right: next_right, right_id: position_id}

      :done ->
        %{state | right: :done}

      {:error, reason} ->
        %{state | right: {:error, reason}}
    end
  end

  defp load_right(state), do: state

  defp find_next(%__MODULE__{
         left: {:error, reason}
       }) do
    {:error, reason}
  end

  defp find_next(%__MODULE__{
         right: {:error, reason}
       }) do
    {:error, reason}
  end

  defp find_next(%__MODULE__{
         left: :done,
         right: :done
       }) do
    :done
  end

  defp find_next(
         %__MODULE__{
           left: :done,
           right_id: right_id
         } = state
       ) do
    {:ok, right_id, %{state | right_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           left_id: left_id,
           right: :done
         } = state
       ) do
    {:ok, left_id, %{state | left_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id == right_id do
    {:ok, left_id, %{state | left_id: nil, right_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id < right_id do
    {:ok, left_id, %{state | left_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id > right_id do
    {:ok, right_id, %{state | right_id: nil}}
  end
end
