defmodule GameDbTest do
  use ExUnit.Case
  doctest GameDb

  test "greets the world" do
    assert GameDb.hello() == :world
  end
end
