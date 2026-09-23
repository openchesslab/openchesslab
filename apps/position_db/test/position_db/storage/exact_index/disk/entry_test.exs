defmodule PositionDB.Storage.ExactIndex.Disk.EntryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Disk.Entry

  describe "size/1" do
    test "returns the hash size plus eight bytes for the position id" do
      assert Entry.size(32) == 40
      assert Entry.size(16) == 24
    end
  end

  describe "encode/2 and decode/2" do
    test "round trips an entry" do
      hash =
        <<
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7
        >>

      encoded =
        Entry.encode(
          hash,
          42
        )

      assert byte_size(encoded) == 16

      assert Entry.decode(
               encoded,
               8
             ) ==
               {:ok, hash, 42}
    end

    test "supports large position ids" do
      hash = <<1, 2, 3, 4>>

      position_id =
        100_000_000_000

      encoded =
        Entry.encode(
          hash,
          position_id
        )

      assert Entry.decode(
               encoded,
               4
             ) ==
               {:ok, hash, position_id}
    end

    test "preserves the complete hash" do
      hash =
        :binary.copy(
          <<255>>,
          32
        )

      encoded =
        Entry.encode(
          hash,
          1
        )

      assert Entry.decode(
               encoded,
               32
             ) ==
               {:ok, hash, 1}
    end

    test "rejects an entry with the wrong size" do
      assert Entry.decode(
               <<1, 2, 3>>,
               4
             ) ==
               {:error, :invalid_entry_size}
    end
  end
end
