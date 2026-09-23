defmodule PositionDB.Storage.ExactIndex.Disk.BucketStore do
  @moduledoc """
  Reads and appends fixed-size entries in exact-index bucket files.
  """

  alias PositionDB.Storage.ExactIndex.Disk.Entry
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  @type t :: %__MODULE__{
          directory: Path.t(),
          hash_size: pos_integer()
        }

  defstruct [
    :directory,
    :hash_size
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
    hash_size =
      Keyword.fetch!(opts, :hash_size)

    if hash_size <= 0 do
      raise ArgumentError,
            "hash_size must be positive"
    end

    %__MODULE__{
      directory: directory,
      hash_size: hash_size
    }
  end

  @spec get(
          t(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, binary(), pos_integer()}
          | :done
          | {:error, :partial_entry}
          | {:error, term()}
  def get(
        %__MODULE__{} = store,
        bucket,
        entry_index
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_integer(entry_index) and
             entry_index >= 0 do
    path =
      Layout.bucket_path(
        store.directory,
        bucket
      )

    entry_size =
      Entry.size(store.hash_size)

    offset =
      entry_index * entry_size

    case :file.open(
           path,
           [:read, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          read_entry(
            file,
            offset,
            entry_size,
            store.hash_size
          )
        after
          :file.close(file)
        end

      {:error, :enoent} ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec append(
          t(),
          non_neg_integer(),
          binary(),
          pos_integer()
        ) ::
          :ok
          | {:error, :invalid_hash_size}
          | {:error, :partial_entry}
          | {:error, term()}
  def append(
        %__MODULE__{} = store,
        bucket,
        hash,
        position_id
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_binary(hash) and
             is_integer(position_id) and
             position_id > 0 do
    if byte_size(hash) == store.hash_size do
      path =
        Layout.bucket_path(
          store.directory,
          bucket
        )

      entry_size =
        Entry.size(store.hash_size)

      with :ok <-
             validate_bucket_size(
               path,
               entry_size
             ) do
        append_entry(
          path,
          Entry.encode(
            hash,
            position_id
          )
        )
      end
    else
      {:error, :invalid_hash_size}
    end
  end

  @spec lookup(
          t(),
          non_neg_integer(),
          binary()
        ) ::
          {:ok, [pos_integer()]}
          | {:error, :invalid_hash_size}
          | {:error, :partial_entry}
          | {:error, term()}
  def lookup(
        %__MODULE__{} = store,
        bucket,
        hash
      )
      when is_integer(bucket) and
             bucket >= 0 and
             is_binary(hash) do
    if byte_size(hash) == store.hash_size do
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
              hash,
              store.hash_size,
              Entry.size(store.hash_size),
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
    else
      {:error, :invalid_hash_size}
    end
  end

  defp lookup_entries(
         file,
         hash,
         hash_size,
         entry_size,
         position_ids
       ) do
    case :file.read(
           file,
           entry_size
         ) do
      {:ok, encoded}
      when byte_size(encoded) == entry_size ->
        {:ok, stored_hash, position_id} =
          Entry.decode(
            encoded,
            hash_size
          )

        position_ids =
          if stored_hash == hash do
            [position_id | position_ids]
          else
            position_ids
          end

        lookup_entries(
          file,
          hash,
          hash_size,
          entry_size,
          position_ids
        )

      {:ok, _partial_entry} ->
        {:error, :partial_entry}

      :eof ->
        {:ok, Enum.reverse(position_ids)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_bucket_size(
         path,
         entry_size
       ) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        if rem(size, entry_size) == 0 do
          :ok
        else
          {:error, :partial_entry}
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_entry(path, entry) do
    case :file.open(
           path,
           [:append, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          :file.write(
            file,
            entry
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_entry(
         file,
         offset,
         entry_size,
         hash_size
       ) do
    case :file.pread(
           file,
           offset,
           entry_size
         ) do
      {:ok, encoded}
      when byte_size(encoded) == entry_size ->
        Entry.decode(
          encoded,
          hash_size
        )

      {:ok, _partial_entry} ->
        {:error, :partial_entry}

      :eof ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end
end
