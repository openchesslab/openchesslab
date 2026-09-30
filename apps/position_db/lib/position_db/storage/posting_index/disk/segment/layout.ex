defmodule PositionDB.Storage.PostingIndex.Disk.Segment.Layout do
  @moduledoc """
  Defines the physical posting-index segment layout and canonical paths.

  A version 1 segment consists of, in order:

    1. a fixed `Segment.Header`
    2. a fixed-size table of unsigned 64-bit term offsets
    3. variable-size `Segment.TermEntry` values sorted by their binary key
    4. posting data addressed by the offsets stored in the term entries

  Every stored offset is absolute from the beginning of the segment
  file.

  Committed segments live in the `segments` directory and use:

      segment-<first_position_id>-<last_position_id>.idx

  Both position IDs are zero-padded to exactly 20 decimal digits. This
  is wide enough for the complete unsigned 64-bit range and preserves
  position-range ordering under lexicographical filename ordering.

  An uncommitted segment uses the same filename followed by `.next`.
  """

  alias PositionDB.Storage.PostingIndex.Disk.Segment.Header
  alias PositionDB.Storage.PostingIndex.Disk.Segment.TermOffsets

  @segments_directory "segments"

  @position_id_width 20

  @segment_filename_pattern ~r/\Asegment-(\d{20})-(\d{20})\.idx\z/

  @max_u64 18_446_744_073_709_551_615

  @spec segments_directory(Path.t()) :: Path.t()
  def segments_directory(directory) when is_binary(directory) do
    Path.join(
      directory,
      @segments_directory
    )
  end

  @spec term_offsets_offset() :: non_neg_integer()
  def term_offsets_offset do
    Header.size()
  end

  @spec term_directory_offset(non_neg_integer()) :: non_neg_integer()
  def term_directory_offset(term_count) when is_integer(term_count) and term_count >= 0 do
    term_offsets_offset() +
      TermOffsets.encoded_size(term_count)
  end

  @spec segment_filename(pos_integer(), pos_integer()) :: String.t()
  def segment_filename(first_position_id, last_position_id)
      when is_integer(first_position_id) and first_position_id > 0 and
             first_position_id <= @max_u64 and is_integer(last_position_id) and
             last_position_id >= first_position_id and last_position_id <= @max_u64 do
    first =
      encode_position_id(first_position_id)

    last =
      encode_position_id(last_position_id)

    "segment-#{first}-#{last}.idx"
  end

  @spec next_segment_filename(pos_integer(), pos_integer()) :: String.t()
  def next_segment_filename(first_position_id, last_position_id)
      when is_integer(first_position_id) and first_position_id > 0 and
             first_position_id <= @max_u64 and is_integer(last_position_id) and
             last_position_id >= first_position_id and last_position_id <= @max_u64 do
    segment_filename(
      first_position_id,
      last_position_id
    ) <> ".next"
  end

  @spec segment_path(Path.t(), pos_integer(), pos_integer()) :: Path.t()
  def segment_path(directory, first_position_id, last_position_id) when is_binary(directory) do
    Path.join(
      segments_directory(directory),
      segment_filename(
        first_position_id,
        last_position_id
      )
    )
  end

  @spec next_segment_path(Path.t(), pos_integer(), pos_integer()) :: Path.t()
  def next_segment_path(directory, first_position_id, last_position_id)
      when is_binary(directory) do
    Path.join(
      segments_directory(directory),
      next_segment_filename(
        first_position_id,
        last_position_id
      )
    )
  end

  @spec parse_segment_filename(String.t()) ::
          {:ok, {pos_integer(), pos_integer()}}
          | {:error, :invalid_segment_filename}
  def parse_segment_filename(filename) when is_binary(filename) do
    case Regex.run(
           @segment_filename_pattern,
           filename,
           capture: :all_but_first
         ) do
      [encoded_first_position_id, encoded_last_position_id] ->
        with {:ok, first_position_id} <-
               decode_position_id(encoded_first_position_id),
             {:ok, last_position_id} <-
               decode_position_id(encoded_last_position_id),
             true <-
               first_position_id <= last_position_id do
          {:ok,
           {
             first_position_id,
             last_position_id
           }}
        else
          _other ->
            {:error, :invalid_segment_filename}
        end

      _other ->
        {:error, :invalid_segment_filename}
    end
  end

  def parse_segment_filename(_filename) do
    {:error, :invalid_segment_filename}
  end

  defp encode_position_id(position_id) do
    position_id
    |> Integer.to_string()
    |> String.pad_leading(
      @position_id_width,
      "0"
    )
  end

  defp decode_position_id(encoded) do
    case Integer.parse(encoded) do
      {position_id, ""}
      when position_id > 0 and position_id <= @max_u64 ->
        {:ok, position_id}

      _other ->
        {:error, :invalid_segment_filename}
    end
  end
end
