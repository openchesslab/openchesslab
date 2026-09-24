defmodule PositionDB.Storage.PostingIndex.Disk.LayoutTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Layout

  describe "bucket_filename/1" do
    test "uses a stable zero-padded filename" do
      assert Layout.bucket_filename(0) ==
               "bucket-00000000.idx"

      assert Layout.bucket_filename(42) ==
               "bucket-00000042.idx"
    end

    test "does not impose an eight-digit limit" do
      assert Layout.bucket_filename(100_000_000) ==
               "bucket-100000000.idx"
    end
  end

  describe "bucket_path/2" do
    test "places the bucket inside the index directory" do
      directory =
        Path.join([
          "var",
          "openchesslab",
          "property-index"
        ])

      assert Layout.bucket_path(
               directory,
               12
             ) ==
               Path.join(
                 directory,
                 "bucket-00000012.idx"
               )
    end
  end
end
