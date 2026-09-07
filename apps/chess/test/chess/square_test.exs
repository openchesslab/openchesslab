defmodule Chess.SquareTest do
  use ExUnit.Case

  alias Chess.Square

  describe "from_algebraic/1" do
    test "converts a1" do
      assert Square.from_algebraic("a1") == 0
    end

    test "converts e4" do
      assert Square.from_algebraic("e4") == 28
    end

    test "converts h8" do
      assert Square.from_algebraic("h8") == 63
    end

    test "rejects invalid squares" do
      assert Square.from_algebraic("x9") == {:error, :invalid_square}
      assert Square.from_algebraic("e9") == {:error, :invalid_square}
      assert Square.from_algebraic("a0") == {:error, :invalid_square}
      assert Square.from_algebraic("ee") == {:error, :invalid_square}
      assert Square.from_algebraic("") == {:error, :invalid_square}
    end
  end

  describe "to_algebraic/1" do
    test "converts 0 to a1" do
      assert Square.to_algebraic(0) == "a1"
    end

    test "converts 28 to e4" do
      assert Square.to_algebraic(28) == "e4"
    end

    test "converts 63 to h8" do
      assert Square.to_algebraic(63) == "h8"
    end
  end

  test "conversion is reversible" do
    for square <- 0..63 do
      assert square
             |> Square.to_algebraic()
             |> Square.from_algebraic() == square
    end
  end
end
