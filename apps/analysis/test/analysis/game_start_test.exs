defmodule Analysis.GameStartTest do
  use ExUnit.Case, async: true

  alias Analysis.GameStart

  test "creates a start context with a fullmove number" do
    start = GameStart.new(37)

    assert GameStart.fullmove_number(start) == 37
  end

  test "standard start begins at fullmove one" do
    start = GameStart.standard()

    assert GameStart.fullmove_number(start) == 1
  end
end
