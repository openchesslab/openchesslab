defmodule PositionDB.AndTest do
  use ExUnit.Case, async: true

  alias PositionDB.And
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor

  test "returns IDs present in both executors" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 3)
      |> PropertyIndex.add({:open_files, :e}, 5)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)
      |> PropertyIndex.add({:open_files, :d}, 5)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = PropertyIndexScan.new(index, {:open_files, :d})

    executor = And.new(left, right)

    assert {:ok, 3, executor} = QueryExecutor.next(executor)
    assert {:ok, 5, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns done when there is no intersection" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = PropertyIndexScan.new(index, {:open_files, :d})

    executor = And.new(left, right)

    assert :done = QueryExecutor.next(executor)
  end

  test "returns multiple consecutive matches in ascending order" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)
      |> PropertyIndex.add({:open_files, :e}, 7)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)
      |> PropertyIndex.add({:open_files, :d}, 7)
      |> PropertyIndex.add({:open_files, :d}, 9)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = PropertyIndexScan.new(index, {:open_files, :d})

    executor = And.new(left, right)

    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert {:ok, 3, executor} = QueryExecutor.next(executor)
    assert {:ok, 7, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end
end
