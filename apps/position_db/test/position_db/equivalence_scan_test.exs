defmodule PositionDB.EquivalenceScanTest do
  use ExUnit.Case, async: true

  alias PositionDB.EquivalenceIndex
  alias PositionDB.EquivalenceScan
  alias PositionDB.PositionStore
  alias PositionDB.QueryExecutor

  defp setup_store(positions) do
    store = PositionStore.new(& &1)

    Enum.reduce(positions, {store, []}, fn position, {store, ids} ->
      {:ok, store, position_id} = PositionStore.put(store, position)
      {store, ids ++ [position_id]}
    end)
  end

  test "returns done when there are no candidates" do
    index = EquivalenceIndex.new()
    {store, _ids} = setup_store([])

    matcher = fn _query, _candidate -> true end

    executor =
      EquivalenceScan.new(
        index,
        store,
        & &1,
        matcher,
        :query
      )

    assert QueryExecutor.next(executor) == :done
  end

  test "returns a matching candidate" do
    candidate = :candidate
    {store, [candidate_id]} = setup_store([candidate])

    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, candidate_id)

    matcher = fn :query, :candidate -> true end

    executor =
      EquivalenceScan.new(
        index,
        store,
        fn _position -> :key end,
        matcher,
        :query
      )

    assert {:ok, ^candidate_id, executor} = QueryExecutor.next(executor)
    assert QueryExecutor.next(executor) == :done
  end

  test "returns multiple matching candidates in id order" do
    positions = [:first, :second, :third]
    {store, [id_1, id_2, id_3]} = setup_store(positions)

    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, id_3)
      |> EquivalenceIndex.add(:key, id_1)
      |> EquivalenceIndex.add(:key, id_2)

    matcher = fn :query, candidate ->
      candidate in positions
    end

    executor =
      EquivalenceScan.new(
        index,
        store,
        fn _position -> :key end,
        matcher,
        :query
      )

    assert {:ok, ^id_1, executor} = QueryExecutor.next(executor)
    assert {:ok, ^id_2, executor} = QueryExecutor.next(executor)
    assert {:ok, ^id_3, executor} = QueryExecutor.next(executor)
    assert QueryExecutor.next(executor) == :done
  end

  test "filters candidates using the matcher" do
    positions = [:accepted, :rejected]
    {store, [accepted_id, rejected_id]} = setup_store(positions)

    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, accepted_id)
      |> EquivalenceIndex.add(:key, rejected_id)

    matcher = fn
      :query, :accepted -> true
      _query, _candidate -> false
    end

    executor =
      EquivalenceScan.new(
        index,
        store,
        fn _position -> :key end,
        matcher,
        :query
      )

    assert {:ok, ^accepted_id, executor} = QueryExecutor.next(executor)
    assert QueryExecutor.next(executor) == :done
  end

  test "uses the equivalence function to find candidates" do
    candidate = :candidate
    {store, [candidate_id]} = setup_store([candidate])

    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:candidate_key, candidate_id)

    equivalence_function = fn :query -> :candidate_key end
    matcher = fn :query, :candidate -> true end

    executor =
      EquivalenceScan.new(
        index,
        store,
        equivalence_function,
        matcher,
        :query
      )

    assert {:ok, ^candidate_id, _executor} =
             QueryExecutor.next(executor)
  end

  test "skips candidates that are no longer in the store" do
    index =
      EquivalenceIndex.new()
      |> EquivalenceIndex.add(:key, 999)

    store = PositionStore.new(& &1)

    matcher = fn _query, _candidate -> true end

    executor =
      EquivalenceScan.new(
        index,
        store,
        fn _position -> :key end,
        matcher,
        :query
      )

    assert QueryExecutor.next(executor) == :done
  end
end
