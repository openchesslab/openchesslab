defmodule PositionDB.Storage.PostingIndex.Disk.BucketStore do
  @moduledoc """
  Reads and durably appends variable-size posting-index entries.

  Bucket files contain consecutive posting entries. Lookup scans
  the bucket sequentially and compares complete keys, so bucket
  hash collisions cannot affect posting-index semantics.
  """

  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  @type t :: %__MODULE__{
          directory: Path.t()
        }

  @type position_id :: pos_integer()

  defstruct [:directory]

  @spec new(Path.t()) :: t()
  def new(directory)
      when is_binary(directory) do
    %__MODULE__{
      directory: directory
    }
  end

  @spec append_durable(
          t(),
          non_neg_integer(),
          binary(),
          position_id()
        ) ::
          :ok
          | {:error, term()}
  def append_durable(
        %__MODULE__{} = store,
        bucket,
        key,
        position_id
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    path =
      Layout.bucket_path(
        store.directory,
        bucket
      )

    entry =
      Entry.encode(
        key,
        position_id
      )

    with {:ok, bucket_state} <-
           bucket_state(path),
         :ok <-
           append_entry_durable(
             store.directory,
             path,
             bucket_state,
             entry
           ) do
      :ok
    end
  end

  @doc """
  Recovers an interrupted durable append for one posting-index entry.

  A matching partial tail is truncated before the expected entry is
  durably restored. An unrelated partial tail is never modified.

  Recovery scans only the affected bucket file to locate variable-size
  entry boundaries.
  """
  @spec recover_pending_append(
          t(),
          non_neg_integer(),
          binary(),
          position_id()
        ) ::
          :ok
          | {:error, :unexpected_partial_entry}
          | {:error, :partial_entry}
          | {:error, :invalid_position_id}
          | {:error, term()}
  def recover_pending_append(
        %__MODULE__{} = store,
        bucket,
        key,
        position_id
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    path =
      Layout.bucket_path(
        store.directory,
        bucket
      )

    entry =
      Entry.encode(
        key,
        position_id
      )

    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} ->
        recover_existing_bucket(
          store,
          path,
          key,
          position_id,
          entry,
          size
        )

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, :enoent} ->
        persist_pending_entry(
          store,
          path,
          :new,
          entry,
          false
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec lookup(
          t(),
          non_neg_integer(),
          binary()
        ) ::
          {:ok, [position_id()]}
          | {:error, :partial_entry}
          | {:error, :invalid_position_id}
          | {:error, term()}
  def lookup(
        %__MODULE__{} = store,
        bucket,
        key
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_binary(key) do
    path =
      Layout.bucket_path(
        store.directory,
        bucket
      )

    case :file.open(
           path,
           [:read, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          lookup_entries(
            file,
            key,
            []
          )
        after
          :file.close(file)
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lookup_entries(
         file,
         key,
         position_ids
       ) do
    header_size =
      Entry.header_size()

    case :file.read(
           file,
           header_size
         ) do
      {:ok, header}
      when byte_size(header) == header_size ->
        with {:ok, key_size, position_id} <-
               Entry.decode_header(header),
             {:ok, stored_key} <-
               read_key(
                 file,
                 key_size
               ) do
          position_ids =
            if stored_key == key do
              [position_id | position_ids]
            else
              position_ids
            end

          lookup_entries(
            file,
            key,
            position_ids
          )
        end

      {:ok, _partial_header} ->
        {:error, :partial_entry}

      :eof ->
        {:ok, Enum.reverse(position_ids)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_key(
         _file,
         0
       ) do
    {:ok, <<>>}
  end

  defp read_key(
         file,
         key_size
       )
       when is_integer(key_size) and
              key_size > 0 do
    case :file.read(
           file,
           key_size
         ) do
      {:ok, key}
      when byte_size(key) == key_size ->
        {:ok, key}

      {:ok, _partial_key} ->
        {:error, :partial_entry}

      :eof ->
        {:error, :partial_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bucket_state(path) do
    case File.stat(path) do
      {:ok, _stat} ->
        {:ok, :existing}

      {:error, :enoent} ->
        {:ok, :new}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_entry_durable(
         directory,
         path,
         bucket_state,
         entry
       ) do
    case :file.open(
           path,
           [:append, :binary, :raw]
         ) do
      {:ok, file} ->
        result =
          try do
            with :ok <-
                   :file.write(
                     file,
                     entry
                   ),
                 :ok <-
                   :file.sync(file) do
              :ok
            end
          after
            :file.close(file)
          end

        with :ok <- result do
          sync_bucket_directory(
            directory,
            bucket_state
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_bucket_directory(
         directory,
         :new
       ) do
    Durability.sync_directory(directory)
  end

  defp sync_bucket_directory(
         _directory,
         :existing
       ) do
    :ok
  end

  defp recover_existing_bucket(
         store,
         path,
         key,
         position_id,
         entry,
         size
       ) do
    case inspect_bucket(
           path,
           size,
           key,
           position_id
         ) do
      {:ok, found?} ->
        persist_pending_entry(
          store,
          path,
          :existing,
          entry,
          found?
        )

      {:partial, offset, partial, found?} ->
        with :ok <-
               validate_partial_entry(
                 partial,
                 entry
               ),
             :ok <-
               truncate_bucket(
                 path,
                 offset
               ),
             :ok <-
               persist_pending_entry(
                 store,
                 path,
                 :existing,
                 entry,
                 found?
               ) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspect_bucket(
         path,
         size,
         key,
         position_id
       ) do
    case :file.open(
           path,
           [:read, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          inspect_entries(
            file,
            0,
            size,
            key,
            position_id,
            false
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspect_entries(
         _file,
         offset,
         size,
         _key,
         _position_id,
         found?
       )
       when offset == size do
    {:ok, found?}
  end

  defp inspect_entries(
         file,
         offset,
         size,
         key,
         position_id,
         found?
       )
       when offset < size do
    header_size =
      Entry.header_size()

    remaining =
      size - offset

    if remaining < header_size do
      with {:ok, partial} <-
             read_exact(
               file,
               offset,
               remaining
             ) do
        {:partial, offset, partial, found?}
      end
    else
      inspect_entry(
        file,
        offset,
        size,
        key,
        position_id,
        found?
      )
    end
  end

  defp inspect_entry(
         file,
         offset,
         size,
         key,
         position_id,
         found?
       ) do
    header_size =
      Entry.header_size()

    with {:ok, header} <-
           read_exact(
             file,
             offset,
             header_size
           ),
         {:ok, key_size, stored_position_id} <-
           Entry.decode_header(header) do
      entry_size =
        header_size + key_size

      remaining =
        size - offset

      if remaining < entry_size do
        with {:ok, partial} <-
               read_exact(
                 file,
                 offset,
                 remaining
               ) do
          {:partial, offset, partial, found?}
        end
      else
        inspect_complete_entry(
          file,
          offset,
          size,
          key,
          position_id,
          found?,
          key_size,
          stored_position_id,
          entry_size
        )
      end
    end
  end

  defp inspect_complete_entry(
         file,
         offset,
         size,
         key,
         position_id,
         found?,
         key_size,
         stored_position_id,
         entry_size
       ) do
    key_offset =
      offset +
        Entry.header_size()

    with {:ok, stored_key} <-
           read_exact(
             file,
             key_offset,
             key_size
           ) do
      found? =
        found? or
          (stored_key == key and
             stored_position_id == position_id)

      inspect_entries(
        file,
        offset + entry_size,
        size,
        key,
        position_id,
        found?
      )
    end
  end

  defp read_exact(
         _file,
         _offset,
         0
       ) do
    {:ok, <<>>}
  end

  defp read_exact(
         file,
         offset,
         size
       )
       when size > 0 do
    case :file.pread(
           file,
           offset,
           size
         ) do
      {:ok, binary}
      when byte_size(binary) == size ->
        {:ok, binary}

      {:ok, _partial} ->
        {:error, :partial_entry}

      :eof ->
        {:error, :partial_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_pending_entry(
         store,
         path,
         bucket_state,
         entry,
         found?
       ) do
    with :ok <-
           ensure_pending_entry(
             store,
             path,
             bucket_state,
             entry,
             found?
           ),
         :ok <-
           Durability.sync_directory(store.directory) do
      :ok
    end
  end

  defp ensure_pending_entry(
         _store,
         path,
         _bucket_state,
         _entry,
         true
       ) do
    Durability.sync_file(path)
  end

  defp ensure_pending_entry(
         store,
         path,
         bucket_state,
         entry,
         false
       ) do
    append_entry_durable(
      store.directory,
      path,
      bucket_state,
      entry
    )
  end

  defp validate_partial_entry(
         partial,
         entry
       ) do
    if byte_size(partial) <=
         byte_size(entry) do
      expected =
        binary_part(
          entry,
          0,
          byte_size(partial)
        )

      if partial == expected do
        :ok
      else
        {:error, :unexpected_partial_entry}
      end
    else
      {:error, :unexpected_partial_entry}
    end
  end

  defp truncate_bucket(
         path,
         size
       ) do
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
          with {:ok, ^size} <-
                 :file.position(
                   file,
                   size
                 ),
               :ok <-
                 :file.truncate(file),
               :ok <-
                 :file.sync(file) do
            :ok
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
