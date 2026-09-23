defmodule PositionDB.Storage.ExactIndex.Disk.Entry do
  @moduledoc """
  Encodes and decodes fixed-size exact-index entries.

  An entry consists of:

    * the complete key hash
    * an unsigned 64-bit position ID
  """

  @position_id_size 8
  @max_position_id 18_446_744_073_709_551_615

  @type position_id :: pos_integer()

  @spec size(pos_integer()) :: pos_integer()
  def size(hash_size)
      when is_integer(hash_size) and
             hash_size > 0 do
    hash_size + @position_id_size
  end

  @spec encode(binary(), position_id()) :: binary()
  def encode(hash, position_id)
      when is_binary(hash) and
             byte_size(hash) > 0 and
             is_integer(position_id) and
             position_id > 0 and
             position_id <= @max_position_id do
    <<hash::binary, position_id::unsigned-big-64>>
  end

  @spec decode(binary(), pos_integer()) ::
          {:ok, binary(), position_id()}
          | {:error, :invalid_entry_size}
  @spec decode(binary(), pos_integer()) ::
          {:ok, binary(), position_id()}
          | {:error, :invalid_entry_size}
  def decode(entry, hash_size)
      when is_binary(entry) and
             is_integer(hash_size) and
             hash_size > 0 do
    expected_size = size(hash_size)

    if byte_size(entry) == expected_size do
      <<hash::binary-size(^hash_size), position_id::unsigned-big-64>> = entry

      {:ok, hash, position_id}
    else
      {:error, :invalid_entry_size}
    end
  end
end
