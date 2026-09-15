defmodule PositionDB.And do
  @moduledoc """
  Executes the intersection of two sorted query executors.
  """

  alias PositionDB.QueryExecutor

  @type position_id :: non_neg_integer()

  @type t :: %__MODULE__{
          left: QueryExecutor.t() | :done,
          right: QueryExecutor.t() | :done,
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

  def next(%__MODULE__{} = state) do
    state
    |> load_left()
    |> maybe_load_right()
    |> find_match()
  end

  defp maybe_load_right(%__MODULE__{left: :done} = state), do: state
  defp maybe_load_right(state), do: load_right(state)

  defp load_left(%__MODULE__{left: :done} = state) do
    state
  end

  defp load_left(%__MODULE__{left_id: nil, left: left} = state) do
    case QueryExecutor.next(left) do
      {:ok, position_id, next_left} ->
        %{state | left: next_left, left_id: position_id}

      :done ->
        %{state | left: :done}
    end
  end

  defp load_left(state), do: state

  defp load_right(%__MODULE__{right: :done} = state) do
    state
  end

  defp load_right(%__MODULE__{right_id: nil, right: right} = state) do
    case QueryExecutor.next(right) do
      {:ok, position_id, next_right} ->
        %{state | right: next_right, right_id: position_id}

      :done ->
        %{state | right: :done}
    end
  end

  defp load_right(state), do: state

  defp find_match(%__MODULE__{left: :done}), do: :done
  defp find_match(%__MODULE__{right: :done}), do: :done

  defp find_match(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id == right_id do
    {:ok, left_id, %{state | left_id: nil, right_id: nil}}
  end

  defp find_match(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id < right_id do
    state
    |> Map.put(:left_id, nil)
    |> next()
  end

  defp find_match(
         %__MODULE__{
           left_id: left_id,
           right_id: right_id
         } = state
       )
       when left_id > right_id do
    state
    |> Map.put(:right_id, nil)
    |> next()
  end
end
