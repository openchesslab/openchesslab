defmodule AnalysisTest do
  use ExUnit.Case
  doctest Analysis

  test "greets the world" do
    assert Analysis.hello() == :world
  end
end
