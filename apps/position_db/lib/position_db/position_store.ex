defmodule PositionDB.PositionStore do
  @moduledoc """
  Logical store for unique positions.

  PositionStore derives exact keys and delegates physical
  persistence, ID allocation and exact-position identity
  to a storage implementation.
  """

  alias PositionDB.Storage.Memory

  @type position_id :: non_neg_integer()
  @type key :: term()

  @type t :: %__MODULE__{
          storage_module: module(),
          storage: term(),
          key_function: (term() -> key())
        }

  @type scan_state :: %{
          storage_module: module(),
          storage_scan: term()
        }

  defstruct [
    :storage_module,
    :storage,
    :key_function
  ]

  @spec new((term() -> key())) :: t()
  def new(key_function)
      when is_function(key_function, 1) do
    new(
      key_function,
      Memory,
      Memory.new()
    )
  end

  @spec new(
          (term() -> key()),
          module(),
          term()
        ) :: t()
  def new(
        key_function,
        storage_module,
        storage
      )
      when is_function(key_function, 1) do
    %__MODULE__{
      storage_module: storage_module,
      storage: storage,
      key_function: key_function
    }
  end

  @spec put(t(), term()) ::
          {:ok, t(), position_id()}
          | {:error, term()}
  def put(%__MODULE__{} = store, position) do
    key =
      store.key_function.(position)

    case store.storage_module.put(
           store.storage,
           key,
           position
         ) do
      {:ok, storage, position_id} ->
        {:ok,
         %{
           store
           | storage: storage
         }, position_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get(t(), position_id()) ::
          {:ok, term()}
          | :not_found
          | {:error, term()}
  def get(%__MODULE__{} = store, position_id) do
    store.storage_module.get(
      store.storage,
      position_id
    )
  end

  @spec find(t(), term()) ::
          {:ok, position_id()}
          | :not_found
          | {:error, term()}
  def find(%__MODULE__{} = store, position) do
    key =
      store.key_function.(position)

    store.storage_module.find(
      store.storage,
      key,
      position
    )
  end

  @spec scan(t()) :: scan_state()
  def scan(%__MODULE__{} = store) do
    %{
      storage_module: store.storage_module,
      storage_scan: store.storage_module.scan(store.storage)
    }
  end

  @spec scan_next(scan_state()) ::
          {:ok, position_id(), scan_state()}
          | :done
  def scan_next(
        %{
          storage_module: storage_module,
          storage_scan: storage_scan
        } = state
      ) do
    case storage_module.scan_next(storage_scan) do
      {:ok, position_id, next_scan} ->
        {:ok, position_id, %{state | storage_scan: next_scan}}

      :done ->
        :done
    end
  end

  @spec cardinality(t()) ::
          non_neg_integer()
  def cardinality(%__MODULE__{} = store) do
    store.storage_module.cardinality(store.storage)
  end
end
