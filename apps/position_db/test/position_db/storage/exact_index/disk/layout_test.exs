defmodule PositionDB.Storage.ExactIndex.Disk.LayoutTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Disk.Layout

  describe "bucket/2" do
    test "maps a hash deterministically to a bucket" do
      hash =
        <<0, 0, 0, 42, 1, 2, 3, 4>>

      assert Layout.bucket(
               hash,
               100
             ) == 42

      assert Layout.bucket(
               hash,
               100
             ) == 42
    end

    test "wraps the hash prefix into the configured bucket count" do
      hash =
        <<0, 0, 1, 1, 1, 2, 3, 4>>

      assert Layout.bucket(
               hash,
               256
             ) == 1
    end

    test "uses only the prefix for bucket selection" do
      hash_a =
        <<0, 0, 0, 7, 1, 2, 3, 4>>

      hash_b =
        <<0, 0, 0, 7, 9, 8, 7, 6>>

      assert Layout.bucket(hash_a, 1_000) ==
               Layout.bucket(hash_b, 1_000)
    end
  end

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
          "exact-index"
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
