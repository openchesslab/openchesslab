defmodule PositionDB.Storage.MemoryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Memory

  test "stores and retrieves a position" do
    storage = Memory.new()

    {storage, position_id} =
      Memory.put(
        storage,
        :key_a,
        :position_a
      )

    assert position_id == 1

    assert Memory.get(
             storage,
             position_id
           ) ==
             {:ok, :position_a}
  end

  test "returns the same id for the same exact position" do
    storage = Memory.new()

    {storage, id_1} =
      Memory.put(
        storage,
        :key_a,
        :position_a
      )

    {_storage, id_2} =
      Memory.put(
        storage,
        :key_a,
        :position_a
      )

    assert id_1 == id_2
  end

  test "supports different positions with the same key" do
    storage = Memory.new()

    {storage, id_1} =
      Memory.put(
        storage,
        :collision,
        :position_a
      )

    {storage, id_2} =
      Memory.put(
        storage,
        :collision,
        :position_b
      )

    assert id_1 != id_2

    assert Memory.find(
             storage,
             :collision,
             :position_a
           ) ==
             {:ok, id_1}

    assert Memory.find(
             storage,
             :collision,
             :position_b
           ) ==
             {:ok, id_2}
  end

  test "scans stored position ids" do
    storage = Memory.new()

    {storage, 1} =
      Memory.put(
        storage,
        :a,
        :position_a
      )

    {storage, 2} =
      Memory.put(
        storage,
        :b,
        :position_b
      )

    scan = Memory.scan(storage)

    assert {:ok, 1, scan} =
             Memory.scan_next(scan)

    assert {:ok, 2, scan} =
             Memory.scan_next(scan)

    assert :done =
             Memory.scan_next(scan)
  end

  test "returns the number of unique positions" do
    storage = Memory.new()

    {storage, _id} =
      Memory.put(
        storage,
        :a,
        :position_a
      )

    {storage, _id} =
      Memory.put(
        storage,
        :a,
        :position_a
      )

    assert Memory.cardinality(storage) == 1
  end
end
