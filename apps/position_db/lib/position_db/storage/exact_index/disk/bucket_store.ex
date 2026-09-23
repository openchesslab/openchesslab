defmodule PositionDB.Storage.ExactIndex.Disk.BucketStore do
  @moduledoc """
  Reads fixed-size entries from exact-index bucket files.
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
