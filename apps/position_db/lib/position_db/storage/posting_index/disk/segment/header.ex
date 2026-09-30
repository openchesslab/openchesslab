defmodule PositionDB.Storage.PostingIndex.Disk.Segment.Header do
  @moduledoc """
  Encodes and decodes the fixed posting-index segment header.

  The version 1 header is exactly 48 bytes:

    * 8 bytes magic
    * 2 bytes version
    * 6 bytes reserved
    * 8 bytes first position ID
    * 8 bytes last position ID
    * 8 bytes term count
    * 8 bytes postings offset

  All integer fields use unsigned big-endian encoding.

  Offsets are absolute byte offsets from the beginning of the segment
  file.
  """

  @magic <<"OCLPSEG", 0>>
  @magic_size byte_size(@magic)

  @version 1

  @reserved <<0::48>>
  @reserved_size byte_size(@reserved)

  @size 48

  @max_u64 18_446_744_073_709_551_615

  @type position_id :: pos_integer()

  @type t :: %__MODULE__{
          first_position_id: position_id(),
          last_position_id: position_id(),
          term_count: non_neg_integer(),
          postings_offset: non_neg_integer()
        }

  @enforce_keys [
    :first_position_id,
    :last_position_id,
    :term_count,
    :postings_offset
  ]

  defstruct [
    :first_position_id,
    :last_position_id,
    :term_count,
    :postings_offset
  ]

  @spec size() :: pos_integer()
  def size do
    @size
  end

  @spec encode(t()) ::
          {:ok, binary()}
          | {:error, :invalid_segment_header}
  def encode(%__MODULE__{} = header) do
    with :ok <-
           validate(header) do
      {:ok,
       <<
         @magic::binary,
         @version::unsigned-big-16,
         @reserved::binary,
         header.first_position_id::unsigned-big-64,
         header.last_position_id::unsigned-big-64,
         header.term_count::unsigned-big-64,
         header.postings_offset::unsigned-big-64
       >>}
    end
  end

  @spec decode(binary()) ::
          {:ok, t()}
          | {:error, :invalid_segment_header}
          | {:error, :invalid_segment_header_magic}
          | {:error, :invalid_segment_header_reserved}
          | {:error, :invalid_segment_header_size}
          | {:error, {:unsupported_segment_header_version, non_neg_integer()}}
  def decode(encoded) when is_binary(encoded) do
    case encoded do
      <<
        magic::binary-size(@magic_size),
        version::unsigned-big-16,
        reserved::binary-size(@reserved_size),
        first_position_id::unsigned-big-64,
        last_position_id::unsigned-big-64,
        term_count::unsigned-big-64,
        postings_offset::unsigned-big-64
      >> ->
        decode_header(
          magic,
          version,
          reserved,
          first_position_id,
          last_position_id,
          term_count,
          postings_offset
        )

      _other ->
        {:error, :invalid_segment_header_size}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_segment_header_size}
  end

  defp decode_header(
         magic,
         _version,
         _reserved,
         _first_position_id,
         _last_position_id,
         _term_count,
         _postings_offset
       )
       when magic != @magic do
    {:error, :invalid_segment_header_magic}
  end

  defp decode_header(
         @magic,
         version,
         _reserved,
         _first_position_id,
         _last_position_id,
         _term_count,
         _postings_offset
       )
       when version != @version do
    {:error, {:unsupported_segment_header_version, version}}
  end

  defp decode_header(
         @magic,
         @version,
         reserved,
         _first_position_id,
         _last_position_id,
         _term_count,
         _postings_offset
       )
       when reserved != @reserved do
    {:error, :invalid_segment_header_reserved}
  end

  defp decode_header(
         @magic,
         @version,
         @reserved,
         first_position_id,
         last_position_id,
         term_count,
         postings_offset
       ) do
    header =
      %__MODULE__{
        first_position_id: first_position_id,
        last_position_id: last_position_id,
        term_count: term_count,
        postings_offset: postings_offset
      }

    case validate(header) do
      :ok ->
        {:ok, header}

      {:error, :invalid_segment_header} ->
        {:error, :invalid_segment_header}
    end
  end

  defp validate(%__MODULE__{
         first_position_id: first_position_id,
         last_position_id: last_position_id,
         term_count: term_count,
         postings_offset: postings_offset
       })
       when is_integer(first_position_id) and first_position_id > 0 and
              first_position_id <= @max_u64 and is_integer(last_position_id) and
              last_position_id >= first_position_id and last_position_id <= @max_u64 and
              is_integer(term_count) and term_count >= 0 and term_count <= @max_u64 and
              is_integer(postings_offset) and postings_offset >= @size and
              postings_offset <= @max_u64 do
    :ok
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_segment_header}
  end
end
