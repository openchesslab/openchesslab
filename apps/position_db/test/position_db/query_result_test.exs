defmodule PositionDB.QueryResultTest do
  use ExUnit.Case, async: true

  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
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
end
