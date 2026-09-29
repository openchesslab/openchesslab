defmodule GameDB.Storage.Disk.RecordStore do
  @moduledoc """
  Append-only storage for variable-length binary game records.

  Record IDs are allocated sequentially starting at one.

  Record payloads are appended to `records.dat`. A fixed-size
  `records.idx` entry stores the byte offset and byte length of
  each record:

    * 8 byte unsigned offset
    * 4 byte unsigned record length

  Appends make record data durable before publishing the
  corresponding index entry.

  When reopening a store, an incomplete index tail and unindexed
  data tail from an interrupted append are discarded.
  """

  @index_entry_size 12
  @max_record_size 0xFFFF_FFFF
  @max_offset 0xFFFF_FFFF_FFFF_FFFF

  @data_filename "records.dat"
  @index_filename "records.idx"

  @type record_id :: pos_integer()

  @type t :: %__MODULE__{
          directory: Path.t(),
          data_path: Path.t(),
          index_path: Path.t()
        }

  @enforce_keys [
    :directory,
    :data_path,
    :index_path
  ]

  defstruct [
    :directory,
    :data_path,
    :index_path
  ]

  @spec create(Path.t()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory) when is_binary(directory) do
    store =
      new(directory)

    case create_directory(directory) do
      :ok ->
        case create_store_files(store) do
          :ok ->
            {:ok, store}

          {:error, reason} ->
            cleanup_failed_create(directory)

            {:error, reason}
        end

      {:error, :eexist} ->
        {:error, :storage_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec open(Path.t()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory) when is_binary(directory) do
    store =
      new(directory)

    with :ok <-
           validate_directory(directory),
         :ok <-
           validate_regular_file(store.data_path),
         :ok <-
           validate_regular_file(store.index_path),
         :ok <-
           recover_index_tail(store),
         :ok <-
           recover_data_tail(store) do
      {:ok, store}
    end
  end

  @spec append(t(), binary()) ::
          {:ok, record_id()}
          | {:error, :invalid_record_size}
          | {:error, term()}
  def append(%__MODULE__{} = store, record) when is_binary(record) do
    record_size =
      byte_size(record)

    if record_size > 0 and
         record_size <= @max_record_size do
      append_record(
        store,
        record,
        record_size
      )
    else
      {:error, :invalid_record_size}
    end
  end

  @spec get(
          t(),
          record_id()
        ) ::
          {:ok, binary()}
          | :not_found
          | {:error, term()}
  def get(%__MODULE__{} = store, record_id) when is_integer(record_id) and record_id > 0 do
    case cardinality(store) do
      {:ok, count}
      when record_id > count ->
        :not_found

      {:ok, _count} ->
        with {:ok, offset, record_size} <-
               read_index_entry(
                 store,
                 record_id
               ) do
          read_record(
            store,
            offset,
            record_size
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, :partial_index_entry}
          | {:error, term()}
  def cardinality(%__MODULE__{} = store) do
    case File.stat(store.index_path) do
      {:ok, %{size: size}} ->
        if rem(
             size,
             @index_entry_size
           ) == 0 do
          {:ok,
           div(
             size,
             @index_entry_size
           )}
        else
          {:error, :partial_index_entry}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp new(directory) do
    %__MODULE__{
      directory: directory,
      data_path:
        Path.join(
          directory,
          @data_filename
        ),
      index_path:
        Path.join(
          directory,
          @index_filename
        )
    }
  end

  defp create_store_files(store) do
    with :ok <-
           create_empty_file(store.data_path) do
      create_empty_file(store.index_path)
    end
  end

  defp append_record(store, record, record_size) do
    with {:ok, count} <-
           cardinality(store),
         {:ok, data_size} <-
           file_size(store.data_path),
         {:ok, index_size} <-
           file_size(store.index_path),
         :ok <-
           validate_offset(data_size) do
      record_id =
        count + 1

      index_entry =
        <<
          data_size::unsigned-big-64,
          record_size::unsigned-big-32
        >>

      do_append(
        store,
        record_id,
        data_size,
        index_size,
        record,
        index_entry
      )
    end
  end

  defp do_append(store, record_id, data_size, index_size, record, index_entry) do
    case append_and_sync(
           store.data_path,
           record
         ) do
      :ok ->
        case append_and_sync(
               store.index_path,
               index_entry
             ) do
          :ok ->
            {:ok, record_id}

          {:error, reason} ->
            rollback_append(
              store,
              data_size,
              index_size,
              reason
            )
        end

      {:error, reason} ->
        rollback_append(
          store,
          data_size,
          index_size,
          reason
        )
    end
  end

  defp rollback_append(store, data_size, index_size, reason) do
    with :ok <-
           truncate_file(
             store.index_path,
             index_size
           ),
         :ok <-
           truncate_file(
             store.data_path,
             data_size
           ) do
      {:error, reason}
    else
      {:error, rollback_reason} ->
        {:error,
         {
           :append_rollback_failed,
           reason,
           rollback_reason
         }}
    end
  end

  defp read_index_entry(store, record_id) do
    offset =
      (record_id - 1) *
        @index_entry_size

    case pread(
           store.index_path,
           offset,
           @index_entry_size
         ) do
      {:ok,
       <<
         record_offset::unsigned-big-64,
         record_size::unsigned-big-32
       >>}
      when record_size > 0 ->
        {:ok, record_offset, record_size}

      {:ok, _entry} ->
        {:error, :invalid_index_entry}

      :eof ->
        {:error, :partial_index_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_record(store, offset, record_size) do
    case pread(
           store.data_path,
           offset,
           record_size
         ) do
      {:ok, record}
      when byte_size(record) ==
             record_size ->
        {:ok, record}

      {:ok, _record} ->
        {:error, :partial_record}

      :eof ->
        {:error, :partial_record}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_index_tail(store) do
    with {:ok, size} <-
           file_size(store.index_path) do
      complete_size =
        div(
          size,
          @index_entry_size
        ) *
          @index_entry_size

      if complete_size == size do
        :ok
      else
        truncate_file(
          store.index_path,
          complete_size
        )
      end
    end
  end

  defp recover_data_tail(store) do
    with {:ok, count} <-
           cardinality(store),
         {:ok, expected_size} <-
           indexed_data_size(
             store,
             count
           ),
         {:ok, actual_size} <-
           file_size(store.data_path) do
      cond do
        actual_size == expected_size ->
          :ok

        actual_size > expected_size ->
          truncate_file(
            store.data_path,
            expected_size
          )

        actual_size < expected_size ->
          {:error,
           {
             :truncated_data,
             expected_size,
             actual_size
           }}
      end
    end
  end

  defp indexed_data_size(_store, 0) do
    {:ok, 0}
  end

  defp indexed_data_size(store, count) do
    with {:ok, offset, record_size} <-
           read_index_entry(
             store,
             count
           ) do
      {:ok,
       offset +
         record_size}
    end
  end

  defp append_and_sync(path, data) do
    case :file.open(
           path,
           [
             :append,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          with :ok <-
                 :file.write(
                   file,
                   data
                 ) do
            :file.sync(file)
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pread(path, offset, size) do
    case :file.open(
           path,
           [
             :read,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          :file.pread(
            file,
            offset,
            size
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp truncate_file(path, size) do
    case :file.open(
           path,
           [
             :read,
             :write,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          with {:ok, _position} <-
                 :file.position(
                   file,
                   size
                 ),
               :ok <-
                 :file.truncate(file) do
            :file.sync(file)
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_directory(directory) do
    with :ok <-
           File.mkdir(directory) do
      sync_directory(Path.dirname(directory))
    end
  end

  defp create_empty_file(path) do
    case :file.open(
           path,
           [
             :write,
             :binary,
             :raw,
             :exclusive
           ]
         ) do
      {:ok, file} ->
        result =
          try do
            :file.sync(file)
          after
            :file.close(file)
          end

        with :ok <- result do
          sync_directory(Path.dirname(path))
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        {:ok, size}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_offset(offset) when offset <= @max_offset do
    :ok
  end

  defp validate_offset(_offset) do
    {:error, :storage_too_large}
  end

  defp validate_directory(directory) do
    case File.stat(directory) do
      {:ok, %{type: :directory}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_regular_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_directory(directory) do
    case :os.type() do
      {:unix, _name} ->
        sync_unix_directory(directory)

      {:win32, _name} ->
        :ok
    end
  end

  defp sync_unix_directory(directory) do
    case :file.open(
           directory,
           [
             :read,
             :directory
           ]
         ) do
      {:ok, file} ->
        try do
          :file.sync(file)
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_failed_create(directory) do
    File.rm_rf(directory)

    :ok
  end
end
