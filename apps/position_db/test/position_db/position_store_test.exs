defmodule PositionDB.PositionStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionStore

  defp key(position), do: :erlang.phash2(position)

  defmodule FailingStorage do
    def put(_storage, _key, _position) do
      {:error, :disk_failure}
    end
  end

  test "new position gets an id" do
    store = PositionStore.new(&key/1)

    {:ok, store, position_id} = PositionStore.put(store, :position_a)

    assert position_id == 1
    assert PositionStore.get(store, position_id) == {:ok, :position_a}
  end

  test "different positions get different ids" do
    store = PositionStore.new(&key/1)

    {:ok, store, id_a} = PositionStore.put(store, :position_a)
    {:ok, _store, id_b} = PositionStore.put(store, :position_b)

    assert id_a == 1
    assert id_b == 2
  end

  test "same position gets the same id" do
    store = PositionStore.new(&key/1)

    {:ok, store, id_1} = PositionStore.put(store, :position_a)
    {:ok, _store, id_2} = PositionStore.put(store, :position_a)

    assert id_1 == id_2
  end

  test "find returns the id of an existing position" do
    store = PositionStore.new(&key/1)

    {:ok, store, position_id} = PositionStore.put(store, :position_a)

    assert PositionStore.find(store, :position_a) == {:ok, position_id}
    assert PositionStore.find(store, :position_b) == :not_found
  end

  test "scans position IDs in ascending order" do
    store = PositionStore.new(& &1)

    {:ok, store, 1} = PositionStore.put(store, :position_1)
    {:ok, store, 2} = PositionStore.put(store, :position_2)
    {:ok, store, 3} = PositionStore.put(store, :position_3)

    state = PositionStore.scan(store)

    assert {:ok, 1, state} = PositionStore.scan_next(state)
    assert {:ok, 2, state} = PositionStore.scan_next(state)
    assert {:ok, 3, state} = PositionStore.scan_next(state)
    assert :done = PositionStore.scan_next(state)
  end

  test "scans an empty store" do
    store = PositionStore.new(& &1)

    state = PositionStore.scan(store)

    assert :done = PositionStore.scan_next(state)
  end

  test "returns the number of stored positions" do
    store = PositionStore.new(& &1)

    assert PositionStore.cardinality(store) == 0

    {:ok, store, _} = PositionStore.put(store, :position_1)
    {:ok, store, _} = PositionStore.put(store, :position_2)

    assert PositionStore.cardinality(store) == 2
  end

  test "counts unique positions" do
    store = PositionStore.new(& &1)

    {:ok, store, _} = PositionStore.put(store, :position)
    {:ok, store, _} = PositionStore.put(store, :position)

    assert PositionStore.cardinality(store) == 1
  end

  test "propagates storage put errors" do
    store =
      PositionStore.new(
        & &1,
        FailingStorage,
        :storage
      )

    assert PositionStore.put(
             store,
             :position
           ) ==
             {:error, :disk_failure}
  end
end
