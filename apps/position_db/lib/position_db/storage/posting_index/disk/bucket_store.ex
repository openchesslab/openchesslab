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
end
