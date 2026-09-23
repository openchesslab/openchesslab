defmodule PositionDB.Storage.Memory do
  @moduledoc """
  In-memory position storage.

  This is the reference storage implementation used by
  PositionDB while no durable storage backend is configured.
  """

  @behaviour PositionDB.Storage

  @type position_id :: PositionDB.Storage.position_id()
  @type key :: PositionDB.Storage.key()

  @type t :: %__MODULE__{
          positions: %{position_id() => term()},
          exact_index: %{
            key() => MapSet.t(position_id())
          },
          next_id: position_id()
        }

  @type scan_state :: %{
          storage: t(),
          next_id: position_id()
        }

  defstruct positions: %{},
            exact_index: %{},
            next_id: 1

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @impl PositionDB.Storage
  def put(%__MODULE__{} = storage, key, position) do
    case find(storage, key, position) do
      {:ok, position_id} ->
        {storage, position_id}

      :not_found ->
        position_id = storage.next_id

        storage = %{
          storage
          | positions:
              Map.put(
                storage.positions,
                position_id,
                position
              ),
            exact_index:
              Map.update(
                storage.exact_index,
                key,
                MapSet.new([position_id]),
                &MapSet.put(&1, position_id)
              ),
            next_id: position_id + 1
        }

        {storage, position_id}
    end
  end

  @impl PositionDB.Storage
  def get(%__MODULE__{} = storage, position_id) do
    case Map.fetch(
           storage.positions,
           position_id
         ) do
      {:ok, position} ->
        {:ok, position}

      :error ->
        :not_found
    end
  end

  @impl PositionDB.Storage
  def find(%__MODULE__{} = storage, key, position) do
    storage.exact_index
    |> Map.get(key, MapSet.new())
    |> Enum.find_value(:not_found, fn position_id ->
      if Map.fetch!(
           storage.positions,
           position_id
         ) == position do
        {:ok, position_id}
      end
    end)
  end

  @impl PositionDB.Storage
  def scan(%__MODULE__{} = storage) do
    %{
      storage: storage,
      next_id: 1
    }
  end

  @impl PositionDB.Storage
  def scan_next(
        %{
          storage: storage,
          next_id: position_id
        } = state
      ) do
    if position_id < storage.next_id do
      {:ok, position_id, %{state | next_id: position_id + 1}}
    else
      :done
    end
  end

  @impl PositionDB.Storage
  def cardinality(%__MODULE__{positions: positions}) do
    map_size(positions)
  end
end
