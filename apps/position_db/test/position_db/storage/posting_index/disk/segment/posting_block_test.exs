defmodule PositionDB.Storage.PostingIndex.Disk.Segment.PostingBlockTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.PostingBlock

  test "uses unsigned 64 bit position ids" do
    assert PostingBlock.id_size() ==
             8

    assert PostingBlock.max_ids() ==
             128

    assert PostingBlock.max_encoded_size() ==
             1024

    assert PostingBlock.encoded_size(128) ==
             1024
  end

  test "encodes and decodes a posting block" do
    position_ids =
      [
        1,
        256,
        65_537
      ]

    assert {:ok, encoded} =
             PostingBlock.encode(position_ids)

    assert encoded ==
             <<
               1::unsigned-big-64,
               256::unsigned-big-64,
               65_537::unsigned-big-64
             >>

    assert PostingBlock.decode(encoded) ==
             {:ok, position_ids}
  end

  test "supports exactly 128 position ids" do
    position_ids =
      Enum.to_list(1..128)

    assert {:ok, encoded} =
             PostingBlock.encode(position_ids)

    assert byte_size(encoded) ==
             1024

    assert PostingBlock.decode(encoded) ==
             {:ok, position_ids}
  end

  test "supports the maximum unsigned 64 bit position id" do
    max_position_id =
      18_446_744_073_709_551_615

    assert {:ok, encoded} =
             PostingBlock.encode([
               max_position_id
             ])

    assert PostingBlock.decode(encoded) ==
             {:ok, [max_position_id]}
  end

  test "rejects an empty posting block" do
    assert PostingBlock.encode([]) ==
             {:error, :invalid_posting_block}

    assert PostingBlock.decode(<<>>) ==
             {:error, :invalid_posting_block_size}
  end

  test "rejects more than 128 position ids" do
    position_ids =
      Enum.to_list(1..129)

    assert PostingBlock.encode(position_ids) ==
             {:error, :invalid_posting_block}

    encoded =
      for position_id <- position_ids,
          into: <<>> do
        <<position_id::unsigned-big-64>>
      end

    assert PostingBlock.decode(encoded) ==
             {:error, :invalid_posting_block_size}
  end

  test "rejects a zero position id" do
    assert PostingBlock.encode([
             0
           ]) ==
             {:error, :invalid_posting_block}

    assert PostingBlock.decode(<<0::unsigned-big-64>>) ==
             {:error, :invalid_posting_block}
  end

  test "rejects duplicate position ids" do
    assert PostingBlock.encode([
             10,
             10
           ]) ==
             {:error, :invalid_posting_block}

    assert PostingBlock.decode(<<
             10::unsigned-big-64,
             10::unsigned-big-64
           >>) ==
             {:error, :invalid_posting_block}
  end

  test "rejects descending position ids" do
    assert PostingBlock.encode([
             11,
             10
           ]) ==
             {:error, :invalid_posting_block}

    assert PostingBlock.decode(<<
             11::unsigned-big-64,
             10::unsigned-big-64
           >>) ==
             {:error, :invalid_posting_block}
  end

  test "rejects a partial position id" do
    assert PostingBlock.decode(<<0::56>>) ==
             {:error, :invalid_posting_block_size}
  end
end
