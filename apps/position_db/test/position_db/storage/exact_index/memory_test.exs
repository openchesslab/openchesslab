defmodule PositionDB.Storage.ExactIndex.MemoryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.ExactIndex.Memory

  test "returns no candidates for an unknown key" do
    index = Memory.new()

    assert Memory.lookup(index, <<"a">>) == []
  end

  test "indexes a position id by key" do
    index =
      Memory.new()
      |> Memory.add(<<"a">>, 1)

    assert Memory.lookup(index, <<"a">>) == [1]
  end

  test "supports multiple candidate ids for the same key" do
    index =
      Memory.new()
      |> Memory.add(<<"collision">>, 1)
      |> Memory.add(<<"collision">>, 2)

    assert MapSet.new(
             Memory.lookup(
               index,
               <<"collision">>
             )
           ) ==
             MapSet.new([1, 2])
  end

  test "does not add the same position id twice" do
    index =
      Memory.new()
      |> Memory.add(<<"a">>, 1)
      |> Memory.add(<<"a">>, 1)

    assert Memory.lookup(index, <<"a">>) == [1]
  end

  test "keeps different keys separate" do
    index =
      Memory.new()
      |> Memory.add(<<"a">>, 1)
      |> Memory.add(<<"b">>, 2)

    assert Memory.lookup(index, <<"a">>) == [1]
    assert Memory.lookup(index, <<"b">>) == [2]
  end
end
