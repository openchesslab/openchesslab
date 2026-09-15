defmodule PositionDB.OrTest do
  use ExUnit.Case, async: true

  alias PositionDB.Or
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndexScan
  alias PositionDB.QueryExecutor

  defp drain(executor) do
    case QueryExecutor.next(executor) do
      {:ok, _position_id, next_executor} ->
        drain(next_executor)

      :done ->
        :ok
    end
  end

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

  test "OR operand order does not change execution cost" do
    {:ok, counter} =
      Agent.start_link(fn ->
        %{
          small: 0,
          large: 0
        }
      end)

    small =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :small, counter, [1]}
      )

    large =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :large, counter, Enum.to_list(1..1000)}
      )

    executor = Or.new(small, large)

    drain(executor)

    first_order_counts = Agent.get(counter, & &1)

    Agent.update(counter, fn _ ->
      %{
        small: 0,
        large: 0
      }
    end)

    small =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :small, counter, [1]}
      )

    large =
      QueryExecutor.new(
        CountingExecutor,
        {self(), :large, counter, Enum.to_list(1..1000)}
      )

    executor = Or.new(large, small)

    drain(executor)

    second_order_counts = Agent.get(counter, & &1)

    assert first_order_counts == second_order_counts
  end
end
