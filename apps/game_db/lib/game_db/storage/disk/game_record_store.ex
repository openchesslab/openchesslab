defmodule GameDB.Storage.Disk.GameRecordStore do
  @moduledoc """
  Stores canonical game records using a record codec and a binary RecordStore.
  """

  alias GameDB.Storage.Disk.RecordStore

  @type t :: %__MODULE__{
          record_store: RecordStore.t(),
          codec: module()
        }

  @enforce_keys [
    :record_store,
    :codec
  ]

  defstruct [
    :record_store,
    :codec
  ]

  @spec new(
          RecordStore.t(),
          module()
        ) :: t()
  def new(
        %RecordStore{} = record_store,
        codec
      )
      when is_atom(codec) do
    %__MODULE__{
      record_store: record_store,
      codec: codec
    }
  end

  @spec append(
          t(),
          term()
        ) ::
          {:ok, pos_integer()}
          | {:error, term()}
  def append(
        %__MODULE__{
          record_store: record_store,
          codec: codec
        },
        record
      ) do
    with {:ok, encoded} <-
           codec.encode(record) do
      RecordStore.append(
        record_store,
        encoded
      )
    end
  end

  @spec get(
          t(),
          pos_integer()
        ) ::
          {:ok, term()}
          | :not_found
          | {:error, term()}
  def get(
        %__MODULE__{
          record_store: record_store,
          codec: codec
        },
        record_id
      ) do
    case RecordStore.get(
           record_store,
           record_id
         ) do
      {:ok, encoded} ->
        codec.decode(encoded)

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality(%__MODULE__{
        record_store: record_store
      }) do
    RecordStore.cardinality(record_store)
  end
end
