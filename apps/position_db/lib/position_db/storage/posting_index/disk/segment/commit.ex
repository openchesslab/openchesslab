defmodule PositionDB.Storage.PostingIndex.Disk.Segment.Commit do
  @moduledoc """
  Durably commits a completed immutable posting-index segment.

  A segment is written to its canonical `.idx.next` path before this
  module is called. Commit then performs the durability sequence:

    1. fsync the completed `.next` file
    2. atomically rename it to the canonical `.idx` path
    3. fsync the containing directory

  The directory sync is performed by `Durability.rename_sibling/2`.

  Committed segments are immutable. An existing canonical segment is
  therefore never intentionally replaced.

  If commit fails before the rename, the `.next` file remains available
  for cleanup or recovery. Readers must only consider canonical `.idx`
  files committed.
  """

  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.PostingIndex.Disk.Segment.Layout

  @spec commit(
          Path.t(),
          pos_integer(),
          pos_integer()
        ) ::
          :ok
          | {:error, :segment_exists}
          | {:error, term()}
  def commit(directory, first_position_id, last_position_id) when is_binary(directory) do
    source =
      Layout.next_segment_path(
        directory,
        first_position_id,
        last_position_id
      )

    destination =
      Layout.segment_path(
        directory,
        first_position_id,
        last_position_id
      )

    with :ok <-
           ensure_destination_missing(destination),
         :ok <-
           Durability.sync_file(source) do
      Durability.rename_sibling(
        source,
        destination
      )
    end
  end

  defp ensure_destination_missing(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        {:error, :segment_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
