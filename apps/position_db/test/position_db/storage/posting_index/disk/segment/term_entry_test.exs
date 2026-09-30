defmodule PositionDB.Storage.PostingIndex.Disk.Segment.TermEntryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.TermEntry

  test "uses a fixed 36 byte term header" do
    assert TermEntry.header_size() ==
             36
  end

  test "encodes and decodes a term entry" do
    entry =
      %TermEntry{
        key: <<"pawn-structure:isolated">>,
        posting_count: 3,
        first_position_id: 7,
        last_position_id: 42,
        postings_offset: 4096
      }

    assert {:ok, encoded} =
             TermEntry.encode(entry)

    assert TermEntry.decode(encoded) ==
             {:ok, entry}
  end

  test "stores term metadata before the key" do
    key =
      <<"material:white-pawn:8">>

    entry =
      %TermEntry{
        key: key,
        posting_count: 10,
        first_position_id: 100,
        last_position_id: 1_000,
        postings_offset: 8192
      }

    assert {:ok, encoded} =
             TermEntry.encode(entry)

    assert <<
             key_size::unsigned-big-32,
             10::unsigned-big-64,
             100::unsigned-big-64,
             1_000::unsigned-big-64,
             8192::unsigned-big-64,
             ^key::binary
           >> = encoded

    assert key_size ==
             byte_size(key)
  end

  test "decodes the fixed term header independently" do
    header =
      <<
        12::unsigned-big-32,
        5::unsigned-big-64,
        10::unsigned-big-64,
        50::unsigned-big-64,
        4096::unsigned-big-64
      >>

    assert TermEntry.decode_header(header) ==
             {:ok, 12, 5, 10, 50, 4096}
  end

  test "supports an empty binary key" do
    entry =
      %TermEntry{
        key: <<>>,
        posting_count: 1,
        first_position_id: 1,
        last_position_id: 1,
        postings_offset: 128
      }

    assert {:ok, encoded} =
             TermEntry.encode(entry)

    assert byte_size(encoded) ==
             TermEntry.header_size()

    assert TermEntry.decode(encoded) ==
             {:ok, entry}
  end

  test "rejects zero posting cardinality" do
    entry =
      %TermEntry{
        key: <<"key">>,
        posting_count: 0,
        first_position_id: 1,
        last_position_id: 1,
        postings_offset: 128
      }

    assert TermEntry.encode(entry) ==
             {:error, :invalid_segment_term_entry}
  end

  test "rejects a zero first position id" do
    entry =
      %TermEntry{
        key: <<"key">>,
        posting_count: 1,
        first_position_id: 0,
        last_position_id: 1,
        postings_offset: 128
      }

    assert TermEntry.encode(entry) ==
             {:error, :invalid_segment_term_entry}
  end

  test "rejects an inverted posting range" do
    entry =
      %TermEntry{
        key: <<"key">>,
        posting_count: 1,
        first_position_id: 10,
        last_position_id: 9,
        postings_offset: 128
      }

    assert TermEntry.encode(entry) ==
             {:error, :invalid_segment_term_entry}
  end

  test "rejects a posting count larger than the represented id range" do
    entry =
      %TermEntry{
        key: <<"key">>,
        posting_count: 3,
        first_position_id: 10,
        last_position_id: 11,
        postings_offset: 128
      }

    assert TermEntry.encode(entry) ==
             {:error, :invalid_segment_term_entry}
  end

  test "rejects a zero postings offset" do
    entry =
      %TermEntry{
        key: <<"key">>,
        posting_count: 1,
        first_position_id: 1,
        last_position_id: 1,
        postings_offset: 0
      }

    assert TermEntry.encode(entry) ==
             {:error, :invalid_segment_term_entry}
  end

  test "rejects an entry shorter than its declared key size" do
    encoded =
      <<
        3::unsigned-big-32,
        1::unsigned-big-64,
        1::unsigned-big-64,
        1::unsigned-big-64,
        128::unsigned-big-64,
        "ab"
      >>

    assert TermEntry.decode(encoded) ==
             {:error, :invalid_segment_term_entry_size}
  end

  test "rejects an entry longer than its declared key size" do
    encoded =
      <<
        2::unsigned-big-32,
        1::unsigned-big-64,
        1::unsigned-big-64,
        1::unsigned-big-64,
        128::unsigned-big-64,
        "abc"
      >>

    assert TermEntry.decode(encoded) ==
             {:error, :invalid_segment_term_entry_size}
  end

  test "rejects a partial fixed header" do
    assert TermEntry.decode_header(<<0::280>>) ==
             {:error, :invalid_segment_term_entry_header_size}
  end
end
