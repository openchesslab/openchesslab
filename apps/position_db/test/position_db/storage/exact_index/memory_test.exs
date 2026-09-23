defmodule PositionDB.Storage.ExactIndex.MemoryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Memory

  test "returns no candidates for an unknown key" do
    index = Memory.new()

    assert Memory.lookup(index, <<"a">>) ==
             {:ok, []}
  end

  test "indexes a position id by key" do
    index = Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"a">>,
               1
             )

    assert Memory.lookup(index, <<"a">>) ==
             {:ok, [1]}
  end

  test "supports multiple candidate ids for the same key" do
    index = Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"collision">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"collision">>,
               2
             )

    assert {:ok, candidates} =
             Memory.lookup(
               index,
               <<"collision">>
             )

    assert MapSet.new(candidates) ==
             MapSet.new([1, 2])
  end

  test "does not add the same position id twice" do
    index = Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"a">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"a">>,
               1
             )

    assert Memory.lookup(index, <<"a">>) ==
             {:ok, [1]}
  end

  test "keeps different keys separate" do
    index = Memory.new()

    assert {:ok, index} =
             Memory.add(
               index,
               <<"a">>,
               1
             )

    assert {:ok, index} =
             Memory.add(
               index,
               <<"b">>,
               2
             )

    assert Memory.lookup(index, <<"a">>) ==
             {:ok, [1]}

    assert Memory.lookup(index, <<"b">>) ==
             {:ok, [2]}
  end
end
