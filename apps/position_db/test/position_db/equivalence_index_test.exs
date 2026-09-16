defmodule PositionDB.EquivalenceIndexTest do
  use ExUnit.Case, async: true

  alias PositionDB.EquivalenceIndex

  test "creates an empty index" do
    index = EquivalenceIndex.new()

    assert EquivalenceIndex.lookup(index, :key) == MapSet.new()
  end

  test "adds a position id for an equivalence key" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new([1])
  end

  test "multiple positions can share an equivalence key" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)
      |> EquivalenceIndex.add(:key, 2)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new([1, 2])
  end

  test "adding the same position id twice does not create a duplicate" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)
      |> EquivalenceIndex.add(:key, 1)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new([1])
  end

  test "lookup returns an empty set for an unknown key" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)

    assert EquivalenceIndex.lookup(index, :other) ==
             MapSet.new()
  end

  test "deletes a position ID from an equivalence key" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)
      |> EquivalenceIndex.add(:key, 2)

    index = EquivalenceIndex.delete(index, :key, 1)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new([2])
  end

  test "removes an equivalence key when its last position ID is deleted" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)

    index = EquivalenceIndex.delete(index, :key, 1)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new()
  end

  test "deleting an unknown position ID does not affect an equivalence key" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 1)

    index = EquivalenceIndex.delete(index, :key, 2)

    assert EquivalenceIndex.lookup(index, :key) ==
             MapSet.new([1])
  end
end
