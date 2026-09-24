defmodule PositionDB.AndTest do
  use ExUnit.Case, async: true

  alias PositionDB.Empty
  alias PositionDB.And
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

  test "stops immediately when the left input is empty" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)

    left = Empty.new()
    right = PropertyIndexScan.new(index, {:open_files, :e})

    executor = And.new(left, right)

    assert QueryExecutor.next(executor) == :done
  end

  test "stops immediately when the right input is empty" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :d}, 2)

    left = PropertyIndexScan.new(index, {:open_files, :e})
    right = Empty.new()

    executor = And.new(left, right)

    assert QueryExecutor.next(executor) == :done
  end

  test "does not evaluate the right input when the left input is done" do
    left =
      QueryExecutor.new(
        TrackingExecutor,
        {self(), :left, :done}
      )

    right =
      QueryExecutor.new(
        TrackingExecutor,
        {self(), :right, {:ok, 1, :next}}
      )

    executor = And.new(left, right)

    assert QueryExecutor.next(executor) == :done
    assert_receive {:next_called, :left}
    refute_receive {:next_called, :right}
  end

  test "placing the smaller operand first avoids unnecessary evaluation" do
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

    executor = And.new(small, large)

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

    executor = And.new(large, small)

    drain(executor)

    second_order_counts = Agent.get(counter, & &1)

    assert first_order_counts == %{small: 1, large: 1}
    assert second_order_counts == %{small: 1, large: 2}
  end

  test "propagates a left executor error without evaluating the right" do
    left =
      QueryExecutor.new(
        TrackingExecutor,
        {
          self(),
          :left,
          {:error, :disk_failure}
        }
      )

    right =
      QueryExecutor.new(
        TrackingExecutor,
        {
          self(),
          :right,
          {:ok, 1, :next}
        }
      )

    executor =
      And.new(
        left,
        right
      )

    assert QueryExecutor.next(executor) ==
             {:error, :disk_failure}

    assert_receive {:next_called, :left}
    refute_receive {:next_called, :right}
  end
end
