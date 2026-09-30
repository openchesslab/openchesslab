defmodule PositionDB.Storage.PostingIndex.Disk.Segment.PostingBlock do
  @moduledoc """
  Encodes and decodes one logical posting block.

  A posting block contains between 1 and 128 position IDs. Each
  position ID is encoded as one unsigned big-endian 64-bit integer.

  Position IDs must be positive and strictly increasing.

  Version 1 deliberately applies no delta encoding, bit packing, block
  header, or compression. The block boundary is logical: a reader knows
  how many IDs remain from term metadata and reads at most 128 IDs, or
  1024 bytes, at a time.
  """

  @id_size 8
  @max_ids 128
  @max_encoded_size @id_size * @max_ids

  @max_u64 18_446_744_073_709_551_615

  @type position_id :: pos_integer()

  @spec id_size() :: pos_integer()
  def id_size do
    @id_size
  end

  @spec max_ids() :: pos_integer()
  def max_ids do
    @max_ids
  end

  @spec max_encoded_size() :: pos_integer()
  def max_encoded_size do
    @max_encoded_size
  end

  @spec encoded_size(1..128) :: pos_integer()
  def encoded_size(position_count)
      when is_integer(position_count) and position_count > 0 and position_count <= @max_ids do
    position_count * @id_size
  end

  @spec encode([position_id()]) ::
          {:ok, binary()}
          | {:error, :invalid_posting_block}
  def encode(position_ids) when is_list(position_ids) do
    with :ok <-
           validate(position_ids) do
      encoded =
        for position_id <- position_ids,
            into: <<>> do
          <<position_id::unsigned-big-64>>
        end

      {:ok, encoded}
    end
  end

  def encode(_position_ids) do
    {:error, :invalid_posting_block}
  end

  @spec decode(binary()) ::
          {:ok, [position_id()]}
          | {:error, :invalid_posting_block}
          | {:error, :invalid_posting_block_size}
  def decode(encoded) when is_binary(encoded) do
    encoded_size =
      byte_size(encoded)

    cond do
      encoded_size == 0 ->
        {:error, :invalid_posting_block_size}

      encoded_size > @max_encoded_size ->
        {:error, :invalid_posting_block_size}

      rem(encoded_size, @id_size) != 0 ->
        {:error, :invalid_posting_block_size}

      true ->
        position_ids =
          for <<position_id::unsigned-big-64 <- encoded>> do
            position_id
          end

        case validate(position_ids) do
          :ok ->
            {:ok, position_ids}

          {:error, :invalid_posting_block} ->
            {:error, :invalid_posting_block}
        end
    end
  end

  def decode(_encoded) do
    {:error, :invalid_posting_block_size}
  end

  defp validate([]) do
    {:error, :invalid_posting_block}
  end

  defp validate([first_position_id | remaining] = position_ids) do
    cond do
      length(position_ids) > @max_ids ->
        {:error, :invalid_posting_block}

      not valid_position_id?(first_position_id) ->
        {:error, :invalid_posting_block}

      true ->
        validate_remaining(
          remaining,
          first_position_id
        )
    end
  end

  defp validate_remaining([], _previous_position_id) do
    :ok
  end

  defp validate_remaining([position_id | remaining], previous_position_id) do
    if valid_position_id?(position_id) and
         position_id > previous_position_id do
      validate_remaining(
        remaining,
        position_id
      )
    else
      {:error, :invalid_posting_block}
    end
  end

  defp valid_position_id?(position_id) do
    is_integer(position_id) and
      position_id > 0 and
      position_id <= @max_u64
  end
end
