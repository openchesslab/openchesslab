defmodule PositionDB.Storage.PostingIndex.Disk.Segment.TermOffsetsTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.TermOffsets

  test "uses one unsigned 64 bit offset per term" do
    assert TermOffsets.offset_size() ==
             8

    assert TermOffsets.encoded_size(3) ==
             24
  end

  test "encodes and decodes term offsets" do
    offsets =
      [
        72,
        128,
        200
      ]

    assert {:ok, encoded} =
             TermOffsets.encode(offsets)

    assert encoded ==
             <<
               72::unsigned-big-64,
               128::unsigned-big-64,
               200::unsigned-big-64
             >>

    assert TermOffsets.decode(
             encoded,
             3
           ) ==
             {:ok, offsets}
  end

  test "supports an empty offset table" do
    assert TermOffsets.encode([]) ==
             {:ok, <<>>}

    assert TermOffsets.decode(
             <<>>,
             0
           ) ==
             {:ok, []}
  end

  test "requires the first term to begin immediately after the offset table" do
    assert TermOffsets.encode([57]) ==
             {:error, :invalid_segment_term_offsets}

    assert TermOffsets.encode([56]) ==
             {:ok, <<56::unsigned-big-64>>}
  end

  test "requires offsets to be strictly increasing" do
    assert TermOffsets.encode([
             64,
             64
           ]) ==
             {:error, :invalid_segment_term_offsets}

    assert TermOffsets.encode([
             64,
             63
           ]) ==
             {:error, :invalid_segment_term_offsets}
  end

  test "rejects an encoded table with the wrong size" do
    encoded =
      <<64::unsigned-big-64>>

    assert TermOffsets.decode(
             encoded,
             2
           ) ==
             {:error, :invalid_segment_term_offsets_size}
  end

  test "rejects a decoded first offset that does not follow the table" do
    encoded =
      <<
        65::unsigned-big-64,
        100::unsigned-big-64
      >>

    assert TermOffsets.decode(
             encoded,
             2
           ) ==
             {:error, :invalid_segment_term_offsets}
  end
end
