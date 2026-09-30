defmodule PositionDB.Storage.PostingIndex.Disk.Segment.LayoutTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.Layout

  describe "physical offsets" do
    test "places the term offset table immediately after the fixed header" do
      assert Layout.term_offsets_offset() ==
               48
    end

    test "places the term directory immediately after the term offset table" do
      assert Layout.term_directory_offset(0) ==
               48

      assert Layout.term_directory_offset(1) ==
               56

      assert Layout.term_directory_offset(3) ==
               72
    end
  end

  describe "segment_filename/2" do
    test "uses canonical 20 digit position ranges" do
      assert Layout.segment_filename(
               1,
               100_000
             ) ==
               "segment-00000000000000000001-00000000000000100000.idx"
    end

    test "supports the maximum unsigned 64 bit position id" do
      max_position_id =
        18_446_744_073_709_551_615

      assert Layout.segment_filename(
               max_position_id,
               max_position_id
             ) ==
               "segment-18446744073709551615-18446744073709551615.idx"
    end
  end

  describe "next_segment_filename/2" do
    test "uses the committed filename followed by next" do
      assert Layout.next_segment_filename(
               1,
               100_000
             ) ==
               "segment-00000000000000000001-00000000000000100000.idx.next"
    end
  end

  describe "parse_segment_filename/1" do
    test "parses a canonical segment filename" do
      assert Layout.parse_segment_filename(
               "segment-00000000000000000001-00000000000000100000.idx"
             ) ==
               {:ok, {1, 100_000}}
    end

    test "round trips canonical filenames" do
      filename =
        Layout.segment_filename(
          42,
          4_294_967_296
        )

      assert Layout.parse_segment_filename(filename) ==
               {:ok, {42, 4_294_967_296}}
    end

    test "rejects position ids that are not exactly 20 digits" do
      assert Layout.parse_segment_filename("segment-1-00000000000000000002.idx") ==
               {:error, :invalid_segment_filename}
    end

    test "rejects zero position ids" do
      assert Layout.parse_segment_filename(
               "segment-00000000000000000000-00000000000000000001.idx"
             ) ==
               {:error, :invalid_segment_filename}
    end

    test "rejects an inverted range" do
      assert Layout.parse_segment_filename(
               "segment-00000000000000000002-00000000000000000001.idx"
             ) ==
               {:error, :invalid_segment_filename}
    end

    test "rejects position ids above unsigned 64 bit range" do
      assert Layout.parse_segment_filename(
               "segment-18446744073709551616-18446744073709551616.idx"
             ) ==
               {:error, :invalid_segment_filename}
    end

    test "does not treat an uncommitted next file as a committed segment" do
      assert Layout.parse_segment_filename(
               "segment-00000000000000000001-00000000000000000002.idx.next"
             ) ==
               {:error, :invalid_segment_filename}
    end
  end

  describe "paths" do
    test "places committed segments inside the segments directory" do
      directory =
        Path.join([
          "var",
          "openchesslab",
          "property-index"
        ])

      assert Layout.segments_directory(directory) ==
               Path.join(
                 directory,
                 "segments"
               )

      assert Layout.segment_path(
               directory,
               1,
               100_000
             ) ==
               Path.join([
                 directory,
                 "segments",
                 "segment-00000000000000000001-00000000000000100000.idx"
               ])
    end

    test "places uncommitted segments beside their committed file" do
      directory =
        Path.join([
          "var",
          "openchesslab",
          "property-index"
        ])

      assert Layout.next_segment_path(
               directory,
               1,
               100_000
             ) ==
               Path.join([
                 directory,
                 "segments",
                 "segment-00000000000000000001-00000000000000100000.idx.next"
               ])
    end
  end
end
