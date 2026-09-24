defmodule PositionDB.Storage.PostingIndex.Disk do
  @moduledoc """
  Disk-backed secondary posting index.

  Stable binary keys are hashed with SHA-256 to select a bucket.
  The complete key remains stored in every posting entry, so hash
  and bucket collisions cannot change lookup semantics.
  """

  @behaviour PositionDB.Storage.PostingIndex

  alias PositionDB.Storage.PostingIndex.Disk.BucketStore
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  @hash_algorithm :sha256

  @type t :: %__MODULE__{
          bucket_store: BucketStore.t(),
          bucket_count: pos_integer()
        }

  defstruct [
    :bucket_store,
    :bucket_count
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    if bucket_count <= 0 do
      raise ArgumentError,
            "bucket_count must be positive"
    end

    %__MODULE__{
      bucket_store: BucketStore.new(directory),
      bucket_count: bucket_count
    }
  end

  @impl PositionDB.Storage.PostingIndex
  def add(
        %__MODULE__{} = index,
        key,
        position_id
      )
      when is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    bucket =
      bucket_for_key(
        index,
        key
      )

    with {:ok, position_ids} <-
           BucketStore.lookup(
             index.bucket_store,
             bucket,
             key
           ) do
      if position_id in position_ids do
        {:ok, index}
      else
        case BucketStore.append_durable(
               index.bucket_store,
               bucket,
               key,
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

  @impl PositionDB.Storage.PostingIndex
  def lookup(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    bucket =
      bucket_for_key(
        index,
        key
      )

    with {:ok, position_ids} <-
           BucketStore.lookup(
             index.bucket_store,
             bucket,
             key
           ) do
      {:ok, Enum.sort(position_ids)}
    end
  end

  @impl PositionDB.Storage.PostingIndex
  def cardinality(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    bucket =
      bucket_for_key(
        index,
        key
      )

    with {:ok, position_ids} <-
           BucketStore.lookup(
             index.bucket_store,
             bucket,
             key
           ) do
      {:ok, length(position_ids)}
    end
  end

  @doc """
  Recovers one interrupted durable posting append.
  """
  @spec recover_pending_append(
          t(),
          binary(),
          pos_integer()
        ) ::
          :ok
          | {:error, term()}
  def recover_pending_append(
        %__MODULE__{} = index,
        key,
        position_id
      )
      when is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    bucket =
      bucket_for_key(
        index,
        key
      )

    BucketStore.recover_pending_append(
      index.bucket_store,
      bucket,
      key,
      position_id
    )
  end

  defp bucket_for_key(
         %__MODULE__{} = index,
         key
       ) do
    hash =
      :crypto.hash(
        @hash_algorithm,
        key
      )

    Layout.bucket(
      hash,
      index.bucket_count
    )
  end
end
