defmodule PositionDB.Storage.Disk do
  @moduledoc """
  Disk-backed position storage.

  Position records are currently read-only. Disk stores can be
  initialized with `create/2` and reopened with `open/2`.

  Combines fixed-size position records, the disk-backed exact
  index and a record codec.

  The encoded record itself is used as the physical exact-index
  key. This keeps the exact index rebuildable from the durable
  record store without depending on application-level key
  functions.

  This module does not yet implement `PositionDB.Storage`.
  The current storage behaviour does not expose disk I/O errors.
  """

  alias PositionDB.Storage.Disk.ExactLookup
  alias PositionDB.Storage.Disk.Manifest
  alias PositionDB.Storage.Disk.ManifestStore
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

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory, opts)
      when is_binary(directory) do
    storage =
      new(
        directory,
        opts
      )

    manifest =
      storage_manifest(storage)

    with {:ok, _encoded} <-
           Manifest.encode(manifest),
         :ok <-
           create_root_directory(directory),
         :ok <-
           File.mkdir(records_directory(directory)),
         :ok <-
           File.mkdir(exact_index_directory(directory)),
         :ok <-
           ManifestStore.create(
             directory,
             manifest
           ) do
      {:ok, storage}
    end
  end

  @spec open(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory, opts)
      when is_binary(directory) do
    codec_module =
      Keyword.fetch!(
        opts,
        :codec
      )

    hash_module =
      Keyword.fetch!(
        opts,
        :hash
      )

    with {:ok, manifest} <-
           ManifestStore.read(directory),
         :ok <-
           validate_runtime_formats(
             manifest,
             codec_module,
             hash_module
           ),
         :ok <-
           validate_storage_directory(
             records_directory(directory),
             :records
           ),
         :ok <-
           validate_storage_directory(
             exact_index_directory(directory),
             :exact_index
           ) do
      storage =
        new(
          directory,
          codec: codec_module,
          records_per_segment: manifest.records_per_segment,
          bucket_count: manifest.exact_bucket_count,
          hash: hash_module
        )

      validate_open_storage(storage)
    end
  end

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

    hash_module =
      Keyword.fetch!(
        opts,
        :hash
      )

    record_store =
      RecordStore.new(
        records_directory(directory),
        record_size: codec_module.record_size(),
        records_per_segment: records_per_segment
      )

    exact_index =
      ExactIndex.new(
        exact_index_directory(directory),
        bucket_count: bucket_count,
        hash: hash_module
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

  @spec find(t(), term(), term()) ::
          {:ok, pos_integer()}
          | :not_found
          | {:error, term()}
  def find(
        %__MODULE__{} = storage,
        _key,
        position
      ) do
    with {:ok, record} <-
           encode_position(
             storage,
             position
           ) do
      ExactLookup.find(
        storage.record_store,
        ExactIndex,
        storage.exact_index,
        record,
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

  defp storage_manifest(%__MODULE__{} = storage) do
    %Manifest{
      record_format_id: storage.codec_module.format_id(),
      record_size: storage.record_store.record_size,
      records_per_segment: storage.record_store.records_per_segment,
      exact_hash_format_id: storage.exact_index.hash_module.format_id(),
      exact_hash_size: storage.exact_index.hash_size,
      exact_bucket_count: storage.exact_index.bucket_count
    }
  end

  defp validate_runtime_formats(
         %Manifest{} = manifest,
         codec_module,
         hash_module
       ) do
    with :ok <-
           validate_format_value(
             :record_format_id,
             manifest.record_format_id,
             codec_module.format_id()
           ),
         :ok <-
           validate_format_value(
             :record_size,
             manifest.record_size,
             codec_module.record_size()
           ),
         :ok <-
           validate_format_value(
             :exact_hash_format_id,
             manifest.exact_hash_format_id,
             hash_module.format_id()
           ),
         :ok <-
           validate_format_value(
             :exact_hash_size,
             manifest.exact_hash_size,
             hash_module.hash_size()
           ) do
      :ok
    end
  end

  defp validate_format_value(
         _field,
         value,
         value
       ) do
    :ok
  end

  defp validate_format_value(
         field,
         persisted,
         configured
       ) do
    {:error, {:storage_format_mismatch, field, persisted, configured}}
  end

  defp validate_storage_directory(
         path,
         name
       ) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        :ok

      {:ok, _stat} ->
        {:error, {:invalid_storage_directory, name}}

      {:error, :enoent} ->
        {:error, {:missing_storage_directory, name}}

      {:error, reason} ->
        {:error, {:storage_directory_error, name, reason}}
    end
  end

  defp validate_open_storage(%__MODULE__{} = storage) do
    case RecordStore.cardinality(storage.record_store) do
      {:ok, _cardinality} ->
        {:ok, storage}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_root_directory(directory) do
    case File.mkdir(directory) do
      :ok ->
        :ok

      {:error, :eexist} ->
        {:error, :storage_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp records_directory(directory) do
    Path.join(
      directory,
      "records"
    )
  end

  defp exact_index_directory(directory) do
    Path.join(
      directory,
      "exact-index"
    )
  end
end
