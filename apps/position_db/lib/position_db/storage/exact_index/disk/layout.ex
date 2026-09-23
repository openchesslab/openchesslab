defmodule PositionDB.Storage.ExactIndex.Disk.Layout do
  @moduledoc """
  Maps exact-key hashes to physical index buckets.
  """

  @type bucket :: non_neg_integer()

  @spec bucket(binary(), pos_integer()) :: bucket()
  def bucket(hash, bucket_count)
      when is_binary(hash) and
             byte_size(hash) >= 4 and
             is_integer(bucket_count) and
             bucket_count > 0 do
    <<prefix::unsigned-big-32, _::binary>> = hash

    rem(prefix, bucket_count)
  end

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
