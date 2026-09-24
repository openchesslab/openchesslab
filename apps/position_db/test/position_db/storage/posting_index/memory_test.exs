defmodule PositionDB.Storage.PostingIndex.MemoryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Memory

  test "adds and looks up a posting" do
    index =
      Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               1
             )

    assert Memory.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}
  end

  test "returns position ids in ascending order" do
    index =
      Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               3
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               2
             )

    assert Memory.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1, 2, 3]}
  end

  test "adding the same posting is idempotent" do
    index =
      Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               1
             )

    assert Memory.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}

    assert Memory.cardinality(
             index,
             <<"key-a">>
           ) ==
             {:ok, 1}
  end

  test "keeps different keys separate" do
    index =
      Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-a">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"key-b">>,
               2
             )

    assert Memory.lookup(
             index,
             <<"key-a">>
           ) ==
             {:ok, [1]}

    assert Memory.lookup(
             index,
             <<"key-b">>
           ) ==
             {:ok, [2]}
  end

  test "returns zero cardinality for an unknown key" do
    index =
      Memory.new()

    assert Memory.cardinality(
             index,
             <<"missing">>
           ) ==
             {:ok, 0}

    assert Memory.lookup(
             index,
             <<"missing">>
           ) ==
             {:ok, []}
  end
end
