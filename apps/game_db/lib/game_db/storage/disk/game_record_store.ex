defmodule GameDB.Storage.Disk.GameRecordStore do
  @moduledoc """
  Stores canonical game records together with their fingerprints.

  The fingerprint is part of the authoritative stored record so
  secondary fingerprint indexes can always be rebuilt from the
  canonical records.

  Physical record format:

    * 32 byte fingerprint
    * encoded canonical game record
  """

  alias GameDB.Storage.Disk.RecordStore

  @fingerprint_size 32

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
  def new(%RecordStore{} = record_store, codec) when is_atom(codec) do
    %__MODULE__{
      record_store: record_store,
      codec: codec
    }
  end

  @spec append(
          t(),
          binary(),
          term()
        ) ::
          {:ok, pos_integer()}
          | {:error, term()}
  def append(%__MODULE__{record_store: record_store, codec: codec}, fingerprint, record)
      when is_binary(fingerprint) do
    with :ok <-
           validate_fingerprint(fingerprint),
         {:ok, encoded} <-
           encode_record(
             codec,
             record
           ) do
      RecordStore.append(
        record_store,
        <<
          fingerprint::binary,
          encoded::binary
        >>
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
  def get(%__MODULE__{codec: codec} = store, record_id) do
    case read_entry(
           store,
           record_id
         ) do
      {:ok, _fingerprint, encoded} ->
        codec.decode(encoded)

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  @spec fingerprint(
          t(),
          pos_integer()
        ) ::
          {:ok, binary()}
          | :not_found
          | {:error, term()}
  def fingerprint(%__MODULE__{} = store, record_id) do
    case read_entry(
           store,
           record_id
         ) do
      {:ok, fingerprint, _encoded} ->
        {:ok, fingerprint}

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality(%__MODULE__{record_store: record_store}) do
    RecordStore.cardinality(record_store)
  end

  defp read_entry(%__MODULE__{record_store: record_store}, record_id) do
    case RecordStore.get(
           record_store,
           record_id
         ) do
      {:ok,
       <<
         fingerprint::binary-size(@fingerprint_size),
         encoded::binary
       >>}
      when byte_size(encoded) > 0 ->
        {:ok, fingerprint, encoded}

      {:ok, _record} ->
        {:error, :invalid_game_record}

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  defp encode_record(codec, record) do
    case codec.encode(record) do
      {:ok, encoded}
      when is_binary(encoded) and
             byte_size(encoded) > 0 ->
        {:ok, encoded}

      {:ok, _encoded} ->
        {:error, :invalid_encoded_record}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_fingerprint(fingerprint) do
    if byte_size(fingerprint) ==
         @fingerprint_size do
      :ok
    else
      {:error, :invalid_fingerprint_size}
    end
  end
end
