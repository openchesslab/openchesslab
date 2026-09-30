defmodule PositionDB.Storage.PostingIndex.Disk.Segment.HeaderTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.Header

  test "uses a fixed 48 byte header" do
    assert Header.size() ==
             48
  end

  test "encodes and decodes a segment header" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 10_000,
        term_count: 42,
        postings_offset: 4096
      }

    assert {:ok, encoded} =
             Header.encode(header)

    assert byte_size(encoded) ==
             48

    assert Header.decode(encoded) ==
             {:ok, header}
  end

  test "uses the canonical version 1 binary layout" do
    header =
      %Header{
        first_position_id: 10,
        last_position_id: 20,
        term_count: 3,
        postings_offset: 512
      }

    assert {:ok, encoded} =
             Header.encode(header)

    assert <<
             "OCLPSEG",
             0,
             1::unsigned-big-16,
             0::48,
             10::unsigned-big-64,
             20::unsigned-big-64,
             3::unsigned-big-64,
             512::unsigned-big-64
           >> = encoded
  end

  test "supports a segment with no terms" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 0,
        postings_offset: Header.size()
      }

    assert {:ok, encoded} =
             Header.encode(header)

    assert Header.decode(encoded) ==
             {:ok, header}
  end

  test "rejects an invalid magic" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert {:ok, encoded} =
             Header.encode(header)

    <<_first_byte, remaining::binary>> =
      encoded

    assert Header.decode(<<0, remaining::binary>>) ==
             {:error, :invalid_segment_header_magic}
  end

  test "rejects an unsupported version" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert {:ok, encoded} =
             Header.encode(header)

    <<
      magic::binary-size(8),
      _version::unsigned-big-16,
      remaining::binary
    >> = encoded

    assert Header.decode(<<
             magic::binary,
             2::unsigned-big-16,
             remaining::binary
           >>) ==
             {:error, {:unsupported_segment_header_version, 2}}
  end

  test "rejects nonzero reserved bytes" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert {:ok, encoded} =
             Header.encode(header)

    <<
      prefix::binary-size(10),
      _reserved::binary-size(6),
      remaining::binary
    >> = encoded

    corrupted =
      <<
        prefix::binary,
        0,
        0,
        0,
        0,
        0,
        1,
        remaining::binary
      >>

    assert Header.decode(corrupted) ==
             {:error, :invalid_segment_header_reserved}
  end

  test "rejects a truncated header" do
    assert Header.decode(<<0::376>>) ==
             {:error, :invalid_segment_header_size}
  end

  test "rejects trailing bytes" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert {:ok, encoded} =
             Header.encode(header)

    assert Header.decode(<<encoded::binary, 0>>) ==
             {:error, :invalid_segment_header_size}
  end

  test "rejects a zero first position id" do
    header =
      %Header{
        first_position_id: 0,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert Header.encode(header) ==
             {:error, :invalid_segment_header}
  end

  test "rejects an inverted position range" do
    header =
      %Header{
        first_position_id: 101,
        last_position_id: 100,
        term_count: 1,
        postings_offset: 128
      }

    assert Header.encode(header) ==
             {:error, :invalid_segment_header}
  end

  test "rejects a postings offset inside the fixed header" do
    header =
      %Header{
        first_position_id: 1,
        last_position_id: 100,
        term_count: 1,
        postings_offset: Header.size() - 1
      }

    assert Header.encode(header) ==
             {:error, :invalid_segment_header}
  end
end
