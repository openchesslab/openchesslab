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
    recover_pending_appends(
      store,
      bucket,
      [
        {
          key,
          position_id
        }
      ]
    )
  end

  @type posting :: {binary(), position_id()}

  @doc """
  Recovers all expected posting entries for one logical indexing unit.

  Complete expected entries are preserved. If the bucket ends in a
  partial entry, that tail is only truncated when it matches a prefix
  of one of the expected entries.

  Missing expected entries are then appended durably.
  """
  @spec recover_pending_appends(
          t(),
          non_neg_integer(),
          [posting()]
        ) ::
          :ok
          | {:error, :unexpected_partial_entry}
          | {:error, :partial_entry}
          | {:error, :invalid_position_id}
          | {:error, term()}
  def recover_pending_appends(
        %__MODULE__{} = store,
        bucket,
        postings
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_list(postings) and
             postings != [] do
    expected =
      postings
      |> Enum.uniq()
      |> Enum.map(fn {key, position_id}
                     when is_binary(key) and
                            is_integer(position_id) and
                            position_id > 0 ->
        {
          {key, position_id},
          Entry.encode(
            key,
            position_id
          )
        }
      end)

    path =
      Layout.bucket_path(
        store.directory,
        bucket
      )

    case File.stat(path) do
      {:ok,
       %{
         type: :regular,
         size: size
       }} ->
        recover_expected_entries(
          store,
          path,
          expected,
          size
        )

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, :enoent} ->
        persist_missing_entries(
          store,
          path,
          :new,
          expected,
          %{}
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

  defp recover_expected_entries(
         store,
         path,
         expected,
         size
       ) do
    expected_pairs =
      Map.new(
        expected,
        fn {pair, _entry} ->
          {
            pair,
            true
          }
        end
      )

    case inspect_expected_entries(
           path,
           size,
           expected_pairs
         ) do
      {:ok, found} ->
        persist_missing_entries(
          store,
          path,
          :existing,
          expected,
          found
        )

      {:partial, offset, partial, found} ->
        with :ok <-
               validate_expected_partial(
                 partial,
                 expected
               ),
             :ok <-
               truncate_bucket(
                 path,
                 offset
               ),
             :ok <-
               persist_missing_entries(
                 store,
                 path,
                 :existing,
                 expected,
                 found
               ) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspect_expected_entries(
         path,
         size,
         expected
       ) do
    case :file.open(
           path,
           [:read, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          inspect_expected_entries(
            file,
            0,
            size,
            expected,
            %{}
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspect_expected_entries(
         _file,
         offset,
         size,
         _expected,
         found
       )
       when offset == size do
    {:ok, found}
  end

  defp inspect_expected_entries(
         file,
         offset,
         size,
         expected,
         found
       )
       when offset < size do
    header_size =
      Entry.header_size()

    remaining =
      size - offset

    if remaining <
         header_size do
      with {:ok, partial} <-
             read_exact(
               file,
               offset,
               remaining
             ) do
        {:partial, offset, partial, found}
      end
    else
      inspect_expected_entry(
        file,
        offset,
        size,
        expected,
        found
      )
    end
  end

  defp inspect_expected_entry(
         file,
         offset,
         size,
         expected,
         found
       ) do
    header_size =
      Entry.header_size()

    with {:ok, header} <-
           read_exact(
             file,
             offset,
             header_size
           ),
         {:ok, key_size, position_id} <-
           Entry.decode_header(header) do
      entry_size =
        header_size +
          key_size

      remaining =
        size - offset

      if remaining <
           entry_size do
        with {:ok, partial} <-
               read_exact(
                 file,
                 offset,
                 remaining
               ) do
          {:partial, offset, partial, found}
        end
      else
        inspect_complete_expected_entry(
          file,
          offset,
          size,
          expected,
          found,
          key_size,
          position_id,
          entry_size
        )
      end
    end
  end

  defp inspect_complete_expected_entry(
         file,
         offset,
         size,
         expected,
         found,
         key_size,
         position_id,
         entry_size
       ) do
    key_offset =
      offset +
        Entry.header_size()

    with {:ok, key} <-
           read_exact(
             file,
             key_offset,
             key_size
           ) do
      pair =
        {
          key,
          position_id
        }

      found =
        if Map.has_key?(
             expected,
             pair
           ) do
          Map.put(
            found,
            pair,
            true
          )
        else
          found
        end

      inspect_expected_entries(
        file,
        offset + entry_size,
        size,
        expected,
        found
      )
    end
  end

  defp validate_expected_partial(
         partial,
         expected
       ) do
    matches? =
      Enum.any?(
        expected,
        fn {_pair, entry} ->
          partial_matches_entry?(
            partial,
            entry
          )
        end
      )

    if matches? do
      :ok
    else
      {:error, :unexpected_partial_entry}
    end
  end

  defp partial_matches_entry?(
         partial,
         entry
       ) do
    partial_size =
      byte_size(partial)

    partial_size <=
      byte_size(entry) and
      partial ==
        binary_part(
          entry,
          0,
          partial_size
        )
  end

  defp persist_missing_entries(
         store,
         path,
         bucket_state,
         expected,
         found
       ) do
    missing =
      Enum.reject(
        expected,
        fn {pair, _entry} ->
          Map.has_key?(
            found,
            pair
          )
        end
      )

    with :ok <-
           append_missing_entries(
             store,
             path,
             bucket_state,
             missing
           ),
         :ok <-
           Durability.sync_file(path),
         :ok <-
           Durability.sync_directory(store.directory) do
      :ok
    end
  end

  defp append_missing_entries(
         _store,
         _path,
         _bucket_state,
         []
       ) do
    :ok
  end

  defp append_missing_entries(
         store,
         path,
         bucket_state,
         [
           {_pair, entry}
           | rest
         ]
       ) do
    with :ok <-
           append_entry_durable(
             store.directory,
             path,
             bucket_state,
             entry
           ) do
      append_missing_entries(
        store,
        path,
        :existing,
        rest
      )
    end
  end
end
