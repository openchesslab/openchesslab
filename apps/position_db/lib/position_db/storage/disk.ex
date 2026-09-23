defmodule PositionDB.Storage.Disk do
  @moduledoc """
  Read-only disk-backed position storage.

  Combines fixed-size position records, the disk-backed exact
  index and a record codec.

  Exact-index matches are treated as candidates. Exact position
  identity is established by comparing the complete encoded
  record.

  This module does not yet implement `PositionDB.Storage`.
  The current storage behaviour does not expose disk I/O errors.
  """

  alias PositionDB.Storage.Disk.ExactLookup
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

  @type t :: %__MODULE__{
          record_store: RecordStore.t(),
          exact_index: ExactIndex.t(),
          codec_module: module()
        }

  defstruct [
    :record_store,
    :exact_index,
    :codec_module
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
    codec_module =
      Keyword.fetch!(
        opts,
        :codec
      )

    records_per_segment =
      Keyword.fetch!(
        opts,
        :records_per_segment
      )

    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    hash_size =
      Keyword.fetch!(
        opts,
        :hash_size
      )

    hash_function =
      Keyword.fetch!(
        opts,
        :hash_function
      )

    record_store =
      RecordStore.new(
        Path.join(
          directory,
          "records"
        ),
        record_size: codec_module.record_size(),
        records_per_segment: records_per_segment
      )

    exact_index =
      ExactIndex.new(
        Path.join(
          directory,
          "exact-index"
        ),
        bucket_count: bucket_count,
        hash_size: hash_size,
        hash_function: hash_function
      )

    %__MODULE__{
      record_store: record_store,
      exact_index: exact_index,
      codec_module: codec_module
    }
  end

  @spec get(t(), pos_integer()) ::
          {:ok, term()}
          | :not_found
          | {:error, term()}
  def get(
        %__MODULE__{} = storage,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    case RecordStore.get(
           storage.record_store,
           position_id
         ) do
      {:ok, record} ->
        storage.codec_module.decode(record)

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec find(t(), binary(), term()) ::
          {:ok, pos_integer()}
          | :not_found
          | {:error, term()}
  def find(
        %__MODULE__{} = storage,
        key,
        position
      )
      when is_binary(key) do
    with {:ok, record} <-
           encode_position(
             storage,
             position
           ) do
      ExactLookup.find(
        storage.record_store,
        ExactIndex,
        storage.exact_index,
        key,
        record
      )
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality(%__MODULE__{} = storage) do
    RecordStore.cardinality(storage.record_store)
  end

  defp encode_position(
         %__MODULE__{} = storage,
         position
       ) do
    case storage.codec_module.encode(position) do
      {:ok, record}
      when is_binary(record) ->
        if byte_size(record) ==
             storage.record_store.record_size do
          {:ok, record}
        else
          {:error, :invalid_record_size}
        end

      {:ok, _record} ->
        {:error, :invalid_record}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
