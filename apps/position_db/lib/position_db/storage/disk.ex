defmodule PositionDB.Storage.Disk do
  @moduledoc """
  Disk-backed position storage.

  Disk stores can be initialized with `create/2`, reopened with
  `open/2` and updated with crash-durable `put/3` operations.

  Combines fixed-size position records, the disk-backed exact
  index and a record codec.

  The encoded record itself is used as the physical exact-index
  key. This keeps the exact index rebuildable from the durable
  record store without depending on application-level key
  functions.
  """

  @behaviour PositionDB.Storage

  alias PositionDB.Storage.Disk.AppendMarker
  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.Disk.ExactIndexRebuilder
  alias PositionDB.Storage.Disk.ExactLookup
  alias PositionDB.Storage.Disk.Manifest
  alias PositionDB.Storage.Disk.ManifestStore
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

  @type t :: %__MODULE__{
          directory: Path.t(),
          record_store: RecordStore.t(),
          exact_index: ExactIndex.t(),
          codec_module: module(),
          next_id: pos_integer()
        }

  @type scan_state :: %{
          next_id: pos_integer(),
          last_id: non_neg_integer()
        }

  defstruct [
    :directory,
    :record_store,
    :exact_index,
    :codec_module,
    next_id: 1
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
           Durability.create_directory(records_directory(directory)),
         :ok <-
           Durability.create_directory(exact_index_directory(directory)),
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
           ExactIndexRebuilder.recover(exact_index_directory(directory)),
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

      with :ok <-
             recover_pending_append(storage) do
        validate_open_storage(storage)
      end
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
      directory: directory,
      record_store: record_store,
      exact_index: exact_index,
      codec_module: codec_module,
      next_id: 1
    }
  end

  @impl PositionDB.Storage
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

  @impl PositionDB.Storage
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
      find_record(
        storage,
        record
      )
    end
  end

  @impl PositionDB.Storage
  @spec put(t(), term(), term()) ::
          {:ok, t(), pos_integer()}
          | {:error, term()}
  def put(
        %__MODULE__{} = storage,
        _key,
        position
      ) do
    with :ok <-
           ensure_no_pending_append(storage),
         {:ok, record} <-
           encode_position(
             storage,
             position
           ) do
      case find_record(
             storage,
             record
           ) do
        {:ok, position_id} ->
          {:ok, storage, position_id}

        :not_found ->
          append_new_position(
            storage,
            record
          )

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl PositionDB.Storage
  @spec cardinality(t()) :: non_neg_integer()
  def cardinality(%__MODULE__{} = storage) do
    storage.next_id - 1
  end

  @impl PositionDB.Storage
  @spec scan(t()) :: scan_state()
  def scan(%__MODULE__{} = storage) do
    %{
      next_id: 1,
      last_id: storage.next_id - 1
    }
  end

  @impl PositionDB.Storage
  @spec scan_next(scan_state()) ::
          {:ok, pos_integer(), scan_state()}
          | :done
  def scan_next(
        %{
          next_id: next_id,
          last_id: last_id
        } = state
      )
      when next_id <= last_id do
    {:ok, next_id,
     %{
       state
       | next_id: next_id + 1
     }}
  end

  def scan_next(%{
        next_id: next_id,
        last_id: last_id
      })
      when next_id > last_id do
    :done
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
      {:ok, cardinality} ->
        {:ok,
         %{
           storage
           | next_id: cardinality + 1
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_root_directory(directory) do
    case Durability.create_directory(directory) do
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

  defp recover_pending_append(%__MODULE__{} = storage) do
    case AppendMarker.read(storage.directory) do
      :none ->
        :ok

      {:ok, position_id} ->
        recover_pending_append(
          storage,
          position_id
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_pending_append(
         %__MODULE__{} = storage,
         position_id
       ) do
    case RecordStore.recover_pending_append(
           storage.record_store,
           position_id
         ) do
      {:ok, record} ->
        recover_indexed_append(
          storage,
          record,
          position_id
        )

      :not_found ->
        AppendMarker.clear(storage.directory)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_indexed_append(
         %__MODULE__{} = storage,
         record,
         position_id
       ) do
    with :ok <-
           ExactIndex.recover_pending_append(
             storage.exact_index,
             record,
             position_id
           ),
         :ok <-
           AppendMarker.clear(storage.directory) do
      :ok
    end
  end

  defp find_record(
         %__MODULE__{} = storage,
         record
       ) do
    ExactLookup.find(
      storage.record_store,
      ExactIndex,
      storage.exact_index,
      record,
      record
    )
  end

  defp append_new_position(
         %__MODULE__{} = storage,
         record
       ) do
    position_id =
      storage.next_id

    with :ok <-
           AppendMarker.create(
             storage.directory,
             position_id
           ),
         :ok <-
           RecordStore.append(
             storage.record_store,
             position_id,
             record
           ),
         {:ok, exact_index} <-
           ExactIndex.add(
             storage.exact_index,
             record,
             position_id
           ),
         :ok <-
           AppendMarker.clear(storage.directory) do
      {:ok,
       %{
         storage
         | exact_index: exact_index,
           next_id: position_id + 1
       }, position_id}
    end
  end

  defp ensure_no_pending_append(%__MODULE__{} = storage) do
    case AppendMarker.read(storage.directory) do
      :none ->
        :ok

      {:ok, position_id} ->
        {:error, {:incomplete_append, position_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
