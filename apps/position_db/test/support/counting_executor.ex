defmodule CountingExecutor do
  def next({test_pid, label, counter, [id | rest]}) do
    Agent.update(counter, &Map.update!(&1, label, fn count -> count + 1 end))
    {:ok, id, {test_pid, label, counter, rest}}
  end

  def next({_test_pid, _label, _counter, []}) do
    :done
  end
end
