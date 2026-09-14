defmodule PositionDB.OrTest do
  use ExUnit.Case, async: true

  alias PositionDB.Or
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor

  test "returns IDs from both executors without duplicates" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = PropertyIndexScan.new(index, {:open_files, :d})

    executor = Or.new(left, right)

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert {:ok, 3, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns IDs from left when right is empty" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = PropertyIndexScan.new(index, {:open_files, :d})

    executor = Or.new(left, right)

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end
end
