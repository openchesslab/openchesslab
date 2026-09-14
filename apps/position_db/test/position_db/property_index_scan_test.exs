defmodule PositionDB.PropertyIndexScanTest do
  use ExUnit.Case, async: true

  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor

  test "scans position IDs in ascending order" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 7)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 19)
      |> PropertyIndex.add({:open_files, :e}, 1)

    executor =
      PropertyIndexScan.new(
        index,
        {:open_files, :e}
      )

    assert {:ok, 1, executor} = QueryExecutor.next(executor)
    assert {:ok, 2, executor} = QueryExecutor.next(executor)
    assert {:ok, 7, executor} = QueryExecutor.next(executor)
    assert {:ok, 19, executor} = QueryExecutor.next(executor)
    assert :done = QueryExecutor.next(executor)
  end

  test "returns done for an unknown property" do
    index = PropertyIndex.new()

    executor =
      PropertyIndexScan.new(
        index,
        {:open_files, :e}
      )

    assert :done = QueryExecutor.next(executor)
  end
end
