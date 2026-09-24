defmodule PositionDB.Not do
  @moduledoc """
  Executes the difference between a universe executor and a child executor.
  """

  alias PositionDB.QueryExecutor

  @type position_id :: non_neg_integer()

  @type child ::
          QueryExecutor.t()
          | :done
          | {:error, term()}

  @type t :: %__MODULE__{
          universe: child(),
          child: child(),
          universe_id: position_id() | nil,
          child_id: position_id() | nil
        }

  defstruct [
    :universe,
    :child,
    :universe_id,
    :child_id
  ]

  @spec new(QueryExecutor.t(), QueryExecutor.t()) :: QueryExecutor.t()
  def new(universe, child) do
    QueryExecutor.new(
      __MODULE__,
      %__MODULE__{
        universe: universe,
        child: child
      }
    )
  end

  def next(%__MODULE__{} = state) do
    state
    |> load_universe()
    |> maybe_load_child()
    |> find_next()
  end

  defp maybe_load_child(%__MODULE__{universe: :done} = state), do: state

  defp maybe_load_child(
         %__MODULE__{
           universe: {:error, _reason}
         } = state
       ) do
    state
  end

  defp maybe_load_child(state), do: load_child(state)

  defp load_universe(%__MODULE__{universe: :done} = state) do
    state
  end

  defp load_universe(
         %__MODULE__{
           universe: {:error, _reason}
         } = state
       ) do
    state
  end

  defp load_universe(
         %__MODULE__{
           universe_id: nil,
           universe: universe
         } = state
       ) do
    case QueryExecutor.next(universe) do
      {:ok, position_id, next_universe} ->
        %{state | universe: next_universe, universe_id: position_id}

      :done ->
        %{state | universe: :done}

      {:error, reason} ->
        %{state | universe: {:error, reason}}
    end
  end

  defp load_universe(state), do: state

  defp load_child(%__MODULE__{child: :done} = state) do
    state
  end

  defp load_child(
         %__MODULE__{
           child_id: nil,
           child: child
         } = state
       ) do
    case QueryExecutor.next(child) do
      {:ok, position_id, next_child} ->
        %{state | child: next_child, child_id: position_id}

      :done ->
        %{state | child: :done}
    end
  end

  defp load_child(state), do: state

  defp find_next(%__MODULE__{
         universe: {:error, reason}
       }) do
    {:error, reason}
  end

  defp find_next(%__MODULE__{
         child: {:error, reason}
       }) do
    {:error, reason}
  end

  defp find_next(%__MODULE__{universe: :done}), do: :done

  defp find_next(%__MODULE__{child: :done, universe_id: universe_id} = state) do
    {:ok, universe_id, %{state | universe_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           universe_id: universe_id,
           child_id: child_id
         } = state
       )
       when universe_id == child_id do
    state
    |> Map.put(:universe_id, nil)
    |> Map.put(:child_id, nil)
    |> next()
  end

  defp find_next(
         %__MODULE__{
           universe_id: universe_id,
           child_id: child_id
         } = state
       )
       when universe_id < child_id do
    {:ok, universe_id, %{state | universe_id: nil}}
  end

  defp find_next(
         %__MODULE__{
           universe_id: universe_id,
           child_id: child_id
         } = state
       )
       when universe_id > child_id do
    state
    |> Map.put(:child_id, nil)
    |> next()
  end
end
