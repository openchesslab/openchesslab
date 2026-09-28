defmodule PositionDB.QueryResultTest do
  use ExUnit.Case, async: true

  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutionError
  alias PositionDB.QueryExecutor
  alias PositionDB.QueryResult

  test "enumerates position IDs lazily" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)

    executor =
      PropertyIndexScan.new(
        index,
        {:open_files, :e}
      )

    result = QueryResult.new(executor)

    assert Enum.to_list(result) == [1, 2, 3]
  end

  test "supports Enum.take without consuming the complete result" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)

    executor =
      PropertyIndexScan.new(
        index,
        {:open_files, :e}
      )

    result = QueryResult.new(executor)

    assert Enum.take(result, 2) == [1, 2]
  end

  test "raises a query execution error when lazy execution fails" do
    executor =
      QueryExecutor.new(
        TrackingExecutor,
        {
          self(),
          :query,
          {:error, :disk_failure}
        }
      )

    result =
      QueryResult.new(executor)

    assert_raise QueryExecutionError,
                 "query execution failed: :disk_failure",
                 fn ->
                   Enum.to_list(result)
                 end
  end

  test "advances a query result explicitly" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add(
        {:open_files, :e},
        1
      )
      |> PropertyIndex.add(
        {:open_files, :e},
        2
      )

    result =
      QueryResult.new(
        PropertyIndexScan.new(
          index,
          {:open_files, :e}
        )
      )

    assert {:ok, 1, result} =
             QueryResult.next(result)

    assert {:ok, 2, result} =
             QueryResult.next(result)

    assert :done =
             QueryResult.next(result)
  end
end
