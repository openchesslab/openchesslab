defmodule PositionDB.Storage.Disk.LayoutTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.Layout

  test "maps the first position to the start of the first segment" do
    assert Layout.location(
             1,
             67,
             1_000
           ) == {0, 0}
  end

  test "maps positions to fixed-size offsets" do
    assert Layout.location(
             2,
             67,
             1_000
           ) == {0, 67}

    assert Layout.location(
             3,
             67,
             1_000
           ) == {0, 134}
  end

  test "maps the last position in a segment" do
    assert Layout.location(
             1_000,
             67,
             1_000
           ) == {0, 999 * 67}
  end

  test "maps the first position in the next segment" do
    assert Layout.location(
             1_001,
             67,
             1_000
           ) == {1, 0}
  end

  test "maps positions in later segments" do
    assert Layout.location(
             2_002,
             67,
             1_000
           ) == {2, 67}
  end

  test "works with very large position ids" do
    assert Layout.location(
             100_000_000,
             67,
             1_000_000
           ) ==
             {99, 999_999 * 67}
  end

  describe "segment_filename/1" do
    test "uses a stable zero-padded segment name" do
      assert Layout.segment_filename(0) ==
               "segment-00000000.dat"

      assert Layout.segment_filename(1) ==
               "segment-00000001.dat"

      assert Layout.segment_filename(42) ==
               "segment-00000042.dat"
    end

    test "does not impose an eight-digit segment limit" do
      assert Layout.segment_filename(100_000_000) ==
               "segment-100000000.dat"
    end
  end

  describe "segment_path/2" do
    test "places a segment inside the storage directory" do
      directory =
        Path.join([
          "var",
          "openchesslab",
          "positions"
        ])

      assert Layout.segment_path(directory, 12) ==
               Path.join(
                 directory,
                 "segment-00000012.dat"
               )
    end
  end
end
