defmodule PositionDB.Storage.PostingIndex.Disk.Segment.TermOffsets do
  @moduledoc """
  Encodes and decodes the fixed-size term-offset table in a segment.

  The table immediately follows the fixed segment header and contains
  one unsigned 64-bit absolute file offset for every term.

  The first offset therefore points to the byte immediately following
  the offset table. Remaining offsets must be strictly increasing.

  This table allows a future segment reader to binary-search the sorted
  term directory without scanning every preceding variable-size term
  entry.
  """

  alias PositionDB.Storage.PostingIndex.Disk.Segment.Header

  @offset_size 8

  @max_u64 18_446_744_073_709_551_615

  @type offset :: non_neg_integer()

  @spec offset_size() :: pos_integer()
  def offset_size do
    @offset_size
  end

  @spec encoded_size(non_neg_integer()) :: non_neg_integer()
  def encoded_size(term_count) when is_integer(term_count) and term_count >= 0 do
    term_count * @offset_size
  end

  @spec encode([offset()]) ::
          {:ok, binary()}
          | {:error, :invalid_segment_term_offsets}
  def encode(offsets) when is_list(offsets) do
    with :ok <-
           validate(offsets) do
      encoded =
        for offset <- offsets,
            into: <<>> do
          <<offset::unsigned-big-64>>
        end

      {:ok, encoded}
    end
  end

  def encode(_offsets) do
    {:error, :invalid_segment_term_offsets}
  end

  @spec decode(binary(), non_neg_integer()) ::
          {:ok, [offset()]}
          | {:error, :invalid_segment_term_offsets}
          | {:error, :invalid_segment_term_offsets_size}
  def decode(encoded, term_count)
      when is_binary(encoded) and is_integer(term_count) and term_count >= 0 do
    expected_size =
      encoded_size(term_count)

    if byte_size(encoded) ==
         expected_size do
      offsets =
        for <<offset::unsigned-big-64 <- encoded>> do
          offset
        end

      case validate(offsets) do
        :ok ->
          {:ok, offsets}

        {:error, :invalid_segment_term_offsets} ->
          {:error, :invalid_segment_term_offsets}
      end
    else
      {:error, :invalid_segment_term_offsets_size}
    end
  end

  def decode(_encoded, _term_count) do
    {:error, :invalid_segment_term_offsets_size}
  end

  defp validate([]) do
    :ok
  end

  defp validate(offsets) do
    first_term_offset =
      Header.size() +
        encoded_size(length(offsets))

    case offsets do
      [^first_term_offset | remaining] ->
        validate_remaining(
          remaining,
          first_term_offset
        )

      _other ->
        {:error, :invalid_segment_term_offsets}
    end
  end

  defp validate_remaining([], _previous_offset) do
    :ok
  end

  defp validate_remaining([offset | remaining], previous_offset)
       when is_integer(offset) and offset > previous_offset and offset <= @max_u64 do
    validate_remaining(
      remaining,
      offset
    )
  end

  defp validate_remaining(_remaining, _previous_offset) do
    {:error, :invalid_segment_term_offsets}
  end
end
