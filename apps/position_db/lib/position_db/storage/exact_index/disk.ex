defmodule PositionDB.Storage.ExactIndex.Disk do
  @moduledoc """
  Disk-backed exact position index.

  Exact keys are hashed into buckets. Lookup returns candidate
  position IDs whose complete position records must still be
  compared by the caller.
  """

  @behaviour PositionDB.Storage.ExactIndex

  alias PositionDB.Storage.ExactIndex.Disk.BucketStore
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  @type t :: %__MODULE__{
          bucket_store: BucketStore.t(),
          bucket_count: pos_integer(),
          hash_size: pos_integer(),
          hash_module: module()
        }

  defstruct [
    :bucket_store,
    :bucket_count,
    :hash_size,
    :hash_module
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
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

    hash_size =
      hash_module.hash_size()

    if bucket_count <= 0 do
      raise ArgumentError,
            "bucket_count must be positive"
    end

    if hash_size < 4 do
      raise ArgumentError,
            "hash_size must be at least 4 bytes"
    end

    %__MODULE__{
      bucket_store:
        BucketStore.new(
          directory,
          hash_size: hash_size
        ),
      bucket_count: bucket_count,
      hash_size: hash_size,
      hash_module: hash_module
    }
  end

  @impl PositionDB.Storage.ExactIndex
  def lookup(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    with {:ok, hash} <-
           key_hash(
             index,
             key
           ) do
      bucket =
        Layout.bucket(
          hash,
          index.bucket_count
        )

      BucketStore.lookup(
        index.bucket_store,
        bucket,
        hash
      )
    end
  end

  @impl PositionDB.Storage.ExactIndex
  def add(
        %__MODULE__{} = index,
        key,
        position_id
      )
      when is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    with {:ok, hash} <-
           key_hash(
             index,
             key
           ),
         bucket <-
           Layout.bucket(
             hash,
             index.bucket_count
           ),
         {:ok, candidates} <-
           BucketStore.lookup(
             index.bucket_store,
             bucket,
             hash
           ) do
      if position_id in candidates do
        {:ok, index}
      else
        case BucketStore.append(
               index.bucket_store,
               bucket,
               hash,
               position_id
             ) do
          :ok ->
            {:ok, index}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp key_hash(
         %__MODULE__{} = index,
         key
       ) do
    case index.hash_module.hash(key) do
      {:ok, hash}
      when is_binary(hash) ->
        if byte_size(hash) ==
             index.hash_size do
          {:ok, hash}
        else
          {:error, {:invalid_hash_size, index.hash_size, byte_size(hash)}}
        end

      {:ok, _hash} ->
        {:error, :invalid_hash}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :invalid_hash}
    end
  end
end
