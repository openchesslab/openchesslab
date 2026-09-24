defmodule PositionDB.Storage.PostingIndex.Disk.Layout do
  @moduledoc """
  Maps posting-index buckets to physical index files.
  """

  @type bucket :: non_neg_integer()

  @spec bucket_filename(bucket()) :: String.t()
  def bucket_filename(bucket)
      when is_integer(bucket) and
             bucket >= 0 do
    bucket
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
    |> then(&"bucket-#{&1}.idx")
  end

  @spec bucket_path(Path.t(), bucket()) :: Path.t()
  def bucket_path(directory, bucket)
      when is_binary(directory) and
             is_integer(bucket) and
             bucket >= 0 do
    Path.join(
      directory,
      bucket_filename(bucket)
    )
  end
end
