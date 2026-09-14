defmodule PositionDB.PositionStore do
  @moduledoc """
  In-memory store for unique positions.
  """

  @type position_id :: non_neg_integer()
  @type key :: term()

  @type t :: %__MODULE__{
          positions: %{position_id() => term()},
          exact_index: %{key() => MapSet.t(position_id())},
          next_id: position_id(),
          key_function: (term() -> key())
        }

  defstruct positions: %{},
            exact_index: %{},
            next_id: 1,
            key_function: nil

  @spec new((term() -> key())) :: t()
  def new(key_function) when is_function(key_function, 1) do
    %__MODULE__{
      key_function: key_function
    }
  end

  @spec put(t(), term()) :: {t(), position_id()}
  def put(%__MODULE__{} = store, position) do
    key = store.key_function.(position)

    case find_by_key(store, key, position) do
      {:ok, position_id} ->
        {store, position_id}

      :not_found ->
        position_id = store.next_id

        store = %{
          store
          | positions: Map.put(store.positions, position_id, position),
            exact_index:
              Map.update(
                store.exact_index,
                key,
                MapSet.new([position_id]),
                &MapSet.put(&1, position_id)
              ),
            next_id: position_id + 1
        }

        {store, position_id}
    end
  end

  @spec get(t(), position_id()) :: {:ok, term()} | :not_found
  def get(%__MODULE__{} = store, position_id) do
    case Map.fetch(store.positions, position_id) do
      {:ok, position} -> {:ok, position}
      :error -> :not_found
    end
  end

  @spec find(t(), term()) :: {:ok, position_id()} | :not_found
  def find(%__MODULE__{} = store, position) do
    key = store.key_function.(position)
    find_by_key(store, key, position)
  end

  defp find_by_key(store, key, position) do
    store.exact_index
    |> Map.get(key, MapSet.new())
    |> Enum.find_value(:not_found, fn position_id ->
      if Map.fetch!(store.positions, position_id) == position do
        {:ok, position_id}
      end
    end)
  end
end
