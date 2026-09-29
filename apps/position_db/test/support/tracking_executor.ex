defmodule TrackingExecutor do
  @moduledoc false
  def next({test_pid, label, result}) do
    send(test_pid, {:next_called, label})
    result
  end
end
