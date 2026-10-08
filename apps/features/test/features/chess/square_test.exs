defmodule Features.Chess.SquareTest do
  use ExUnit.Case, async: true

  alias Features.Chess.Square

  test "parse and to_string round-trip every square" do
    for square <- 0..63 do
      assert square |> Square.to_string() |> Square.parse() == square
    end
  end

  test "parse converts algebraic notation to an index" do
    assert Square.parse("a1") == 0
    assert Square.parse("h1") == 7
    assert Square.parse("a8") == 56
    assert Square.parse("e4") == 28
    assert Square.parse("h8") == 63
  end

  test "to_string converts an index to algebraic notation" do
    assert Square.to_string(0) == "a1"
    assert Square.to_string(7) == "h1"
    assert Square.to_string(56) == "a8"
    assert Square.to_string(28) == "e4"
    assert Square.to_string(63) == "h8"
  end

  test "file, rank and new" do
    assert Square.file(28) == 4
    assert Square.rank(28) == 3
    assert Square.new(4, 3) == 28
    assert Square.new(0, 0) == 0
    assert Square.new(7, 7) == 63
  end

  test "parse raises on invalid input" do
    assert_raise ArgumentError, fn -> Square.parse("e9") end
    assert_raise ArgumentError, fn -> Square.parse("i4") end
    assert_raise ArgumentError, fn -> Square.parse("e") end
    assert_raise ArgumentError, fn -> Square.parse("e44") end
  end
end
