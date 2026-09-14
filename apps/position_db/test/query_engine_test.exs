defmodule PositionDB.QueryEngineTest do
  use ExUnit.Case, async: true

  alias PositionDB.QueryEngine
  alias PositionDB.PropertyIndex

  test "property query returns matching positions" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)

    query = {:property, :open_files, :e}

    assert QueryEngine.execute(index, query) ==
             MapSet.new([1, 2])
  end

  test "and query returns intersection" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

    assert QueryEngine.execute(index, query) ==
             MapSet.new([2])
  end

  test "and query with multiple properties" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)
      |> PropertyIndex.add({:open_files, :d}, 4)
      |> PropertyIndex.add({:open_files, :c}, 3)
      |> PropertyIndex.add({:open_files, :c}, 4)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d},
         {:property, :open_files, :c}
       ]}

    assert QueryEngine.execute(index, query) ==
             MapSet.new([3])
  end

  test "or query returns union" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :d}, 2)
      |> PropertyIndex.add({:open_files, :d}, 3)

    query =
      {:or,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

    assert QueryEngine.execute(index, query) ==
             MapSet.new([1, 2, 3])
  end
end
