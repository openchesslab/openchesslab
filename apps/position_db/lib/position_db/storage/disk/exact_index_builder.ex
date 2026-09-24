defmodule PositionDB.Storage.Disk.ExactIndexBuilder do
  @moduledoc """
  Builds a new disk exact index from authoritative position records.

  The destination exact index must be empty. Records are scanned in
  position-ID order and appended directly to their hash buckets.

  This avoids lookup-before-append work during a full rebuild.
  """

  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex
  alias PositionDB.Storage.ExactIndex.Disk.BucketStore
  alias PositionDB.Storage.ExactIndex.Disk.Layout

  @spec build(
          RecordStore.t(),
          ExactIndex.t()
        ) ::
          {:ok, ExactIndex.t()}
          | {:error, term()}
  def build(
        %RecordStore{} = record_store,
        %ExactIndex{} = exact_index
      ) do
    with :ok <-
           ensure_empty(exact_index),
         {:ok, scan} <-
           RecordStore.scan(record_store),
         :ok <-
           build_entries(
             record_store,
             exact_index,
             scan
           ) do
      {:ok, exact_index}
    end
  end

  defp build_entries(
         record_store,
         exact_index,
         scan
       ) do
    case RecordStore.scan_next(scan) do
      {:ok, position_id, next_scan} ->
        with {:ok, record} <-
               read_record(
                 record_store,
                 position_id
               ),
             :ok <-
               append_entry(
                 exact_index,
                 record,
                 position_id
               ) do
          build_entries(
            record_store,
            exact_index,
            next_scan
          )
        end

      :done ->
        :ok
    end
  end

  defp read_record(
         record_store,
         position_id
       ) do
    case RecordStore.get(
           record_store,
           position_id
         ) do
      {:ok, record} ->
        {:ok, record}

      :not_found ->
        {:error, {:missing_position_record, position_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_entry(
         exact_index,
         record,
         position_id
       ) do
    with {:ok, hash} <-
           ExactIndex.key_hash(
             exact_index,
             record
           ) do
      bucket =
        Layout.bucket(
          hash,
          exact_index.bucket_count
        )

      BucketStore.append(
        exact_index.bucket_store,
        bucket,
        hash,
        position_id
      )
    end
  end

  defp ensure_empty(%ExactIndex{} = exact_index) do
    directory =
      exact_index.bucket_store.directory

    case File.ls(directory) do
      {:ok, []} ->
        :ok

      {:ok, _entries} ->
        {:error, :exact_index_not_empty}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
