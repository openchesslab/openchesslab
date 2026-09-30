defmodule PositionDB.Storage.PostingIndex.Disk.Segment.TermEntry do
  @moduledoc """
  Encodes and decodes one entry in a segment's sorted term directory.

  A term entry consists of:

    * 4 bytes key size
    * 8 bytes posting count
    * 8 bytes first position ID
    * 8 bytes last position ID
    * 8 bytes postings offset
    * N bytes key

  All integer fields use unsigned big-endian encoding.

  `postings_offset` is an absolute byte offset from the beginning of
  the segment file.

  A term entry always represents at least one posting. Because posting
  IDs are unique and strictly increasing, the posting count cannot be
  larger than the inclusive range between the first and last posting.
  """

  @header_size 36

  @max_u32 4_294_967_295
  @max_u64 18_446_744_073_709_551_615

  @type position_id :: pos_integer()

  @type t :: %__MODULE__{
          key: binary(),
          posting_count: pos_integer(),
          first_position_id: position_id(),
          last_position_id: position_id(),
          postings_offset: pos_integer()
        }

  @enforce_keys [
    :key,
    :posting_count,
    :first_position_id,
    :last_position_id,
    :postings_offset
  ]

  defstruct [
    :key,
    :posting_count,
    :first_position_id,
    :last_position_id,
    :postings_offset
  ]

  @spec header_size() :: pos_integer()
  def header_size do
    @header_size
  end

  @spec encode(t()) ::
          {:ok, binary()}
          | {:error, :invalid_segment_term_entry}
  def encode(%__MODULE__{} = entry) do
    with :ok <-
           validate(entry) do
      key_size =
        byte_size(entry.key)

      {:ok,
       <<
         key_size::unsigned-big-32,
         entry.posting_count::unsigned-big-64,
         entry.first_position_id::unsigned-big-64,
         entry.last_position_id::unsigned-big-64,
         entry.postings_offset::unsigned-big-64,
         entry.key::binary
       >>}
    end
  end

  @spec decode_header(binary()) ::
          {:ok, non_neg_integer(), pos_integer(), position_id(), position_id(), pos_integer()}
          | {:error, :invalid_segment_term_entry}
          | {:error, :invalid_segment_term_entry_header_size}
  def decode_header(
        <<key_size::unsigned-big-32, posting_count::unsigned-big-64,
          first_position_id::unsigned-big-64, last_position_id::unsigned-big-64,
          postings_offset::unsigned-big-64>>
      ) do
    case validate_metadata(
           posting_count,
           first_position_id,
           last_position_id,
           postings_offset
         ) do
      :ok ->
        {:ok, key_size, posting_count, first_position_id, last_position_id, postings_offset}

      {:error, :invalid_segment_term_entry} ->
        {:error, :invalid_segment_term_entry}
    end
  end

  def decode_header(_encoded) do
    {:error, :invalid_segment_term_entry_header_size}
  end

  @spec decode(binary()) ::
          {:ok, t()}
          | {:error, :invalid_segment_term_entry}
          | {:error, :invalid_segment_term_entry_size}
  def decode(encoded) when is_binary(encoded) do
    case encoded do
      <<
        header::binary-size(@header_size),
        key::binary
      >> ->
        with {:ok, key_size, posting_count, first_position_id, last_position_id, postings_offset} <-
               decode_header(header),
             :ok <-
               validate_key_size(
                 key,
                 key_size
               ) do
          {:ok,
           %__MODULE__{
             key: key,
             posting_count: posting_count,
             first_position_id: first_position_id,
             last_position_id: last_position_id,
             postings_offset: postings_offset
           }}
        else
          {:error, :invalid_segment_term_entry_header_size} ->
            {:error, :invalid_segment_term_entry_size}

          {:error, reason} ->
            {:error, reason}
        end

      _other ->
        {:error, :invalid_segment_term_entry_size}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_segment_term_entry_size}
  end

  defp validate(%__MODULE__{
         key: key,
         posting_count: posting_count,
         first_position_id: first_position_id,
         last_position_id: last_position_id,
         postings_offset: postings_offset
       })
       when is_binary(key) and byte_size(key) <= @max_u32 do
    validate_metadata(
      posting_count,
      first_position_id,
      last_position_id,
      postings_offset
    )
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_segment_term_entry}
  end

  defp validate_metadata(posting_count, first_position_id, last_position_id, postings_offset)
       when is_integer(posting_count) and posting_count > 0 and posting_count <= @max_u64 and
              is_integer(first_position_id) and first_position_id > 0 and
              first_position_id <= @max_u64 and is_integer(last_position_id) and
              last_position_id >= first_position_id and last_position_id <= @max_u64 and
              posting_count <= last_position_id - first_position_id + 1 and
              is_integer(postings_offset) and postings_offset > 0 and postings_offset <= @max_u64 do
    :ok
  end

  defp validate_metadata(_posting_count, _first_position_id, _last_position_id, _postings_offset) do
    {:error, :invalid_segment_term_entry}
  end

  defp validate_key_size(key, key_size) do
    if byte_size(key) ==
         key_size do
      :ok
    else
      {:error, :invalid_segment_term_entry_size}
    end
  end
end
