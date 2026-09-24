defmodule PositionDB.Storage.PostingIndex.Disk.EntryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Entry

  test "encodes and decodes a posting entry" do
    encoded =
      Entry.encode(
        <<"open-files:e">>,
        42
      )

    assert Entry.decode(encoded) ==
             {:ok, <<"open-files:e">>, 42}
  end

  test "stores the key size and position id in the header" do
    key =
      <<"material:white-pawn:8">>

    encoded =
      Entry.encode(
        key,
        123
      )

    header_size = Entry.header_size()

    <<
      header::binary-size(^header_size),
      ^key::binary
    >> = encoded

    assert Entry.decode_header(header) ==
             {:ok, byte_size(key), 123}
  end

  test "supports an empty binary key" do
    encoded =
      Entry.encode(
        <<>>,
        1
      )

    assert byte_size(encoded) ==
             Entry.header_size()

    assert Entry.decode(encoded) ==
             {:ok, <<>>, 1}
  end

  test "rejects a partial header" do
    assert Entry.decode_header(<<0, 0, 0>>) ==
             {:error, :invalid_header_size}
  end

  test "rejects a zero position id" do
    header =
      <<
        3::unsigned-big-32,
        0::unsigned-big-64
      >>

    assert Entry.decode_header(header) ==
             {:error, :invalid_position_id}
  end

  test "rejects an entry shorter than its declared key size" do
    encoded =
      <<
        5::unsigned-big-32,
        1::unsigned-big-64,
        "abc"
      >>

    assert Entry.decode(encoded) ==
             {:error, :invalid_entry_size}
  end

  test "rejects an entry longer than its declared key size" do
    encoded =
      <<
        3::unsigned-big-32,
        1::unsigned-big-64,
        "abcde"
      >>

    assert Entry.decode(encoded) ==
             {:error, :invalid_entry_size}
  end
end
