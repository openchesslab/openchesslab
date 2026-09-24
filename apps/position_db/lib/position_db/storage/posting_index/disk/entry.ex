defmodule PositionDB.Storage.PostingIndex.Disk.Entry do
  @moduledoc """
  Encodes and decodes variable-size posting-index entries.

  An entry consists of:

    * the key size as an unsigned 32-bit integer
    * the position ID as an unsigned 64-bit integer
    * the complete binary key

  The complete key is stored so hash collisions used for bucket
  selection never change posting-index semantics.
  """

  @header_size 12

  @max_key_size 4_294_967_295
  @max_position_id 18_446_744_073_709_551_615

  @type position_id :: pos_integer()

  @spec header_size() :: pos_integer()
  def header_size do
    @header_size
  end

  @spec encode(
          binary(),
          position_id()
        ) :: binary()
  def encode(
        key,
        position_id
      )
      when is_binary(key) and
             byte_size(key) <= @max_key_size and
             is_integer(position_id) and
             position_id > 0 and
             position_id <= @max_position_id do
    key_size =
      byte_size(key)

    <<
      key_size::unsigned-big-32,
      position_id::unsigned-big-64,
      key::binary
    >>
  end

  @spec decode_header(binary()) ::
          {:ok, non_neg_integer(), position_id()}
          | {:error, :invalid_header_size}
          | {:error, :invalid_position_id}
  def decode_header(<<
        key_size::unsigned-big-32,
        position_id::unsigned-big-64
      >>) do
    if position_id > 0 do
      {:ok, key_size, position_id}
    else
      {:error, :invalid_position_id}
    end
  end

  def decode_header(_encoded) do
    {:error, :invalid_header_size}
  end

  @spec decode(binary()) ::
          {:ok, binary(), position_id()}
          | {:error, :invalid_entry_size}
          | {:error, :invalid_position_id}
  def decode(encoded)
      when is_binary(encoded) do
    case encoded do
      <<
        header::binary-size(@header_size),
        key::binary
      >> ->
        with {:ok, key_size, position_id} <-
               decode_header(header),
             :ok <-
               validate_key_size(
                 key,
                 key_size
               ) do
          {:ok, key, position_id}
        end

      _other ->
        {:error, :invalid_entry_size}
    end
  end

  defp validate_key_size(
         key,
         key_size
       ) do
    if byte_size(key) == key_size do
      :ok
    else
      {:error, :invalid_entry_size}
    end
  end
end
