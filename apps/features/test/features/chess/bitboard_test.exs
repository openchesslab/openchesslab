defmodule Features.Chess.BitboardTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Features.Chess.Bitboard

  test "least_square returns the bit index for every single-bit board" do
    for bit <- 0..63 do
      assert Bitboard.least_square(1 <<< bit) == bit
    end
  end

  test "least_square returns the lowest set bit for mixed boards" do
    boards = [
      0b1,
      0b10,
      0b1000_0000,
      1 <<< 63,
      0xFFFFFFFFFFFFFFFF,
      0x0F0F0F0F0F0F0F0F,
      1 <<< 63 ||| 5
    ]

    for board <- boards do
      assert Bitboard.least_square(board) == naive_least_square(board)
    end
  end

  test "squares returns set bits in ascending order" do
    boards = [
      0,
      1,
      1 <<< 63,
      0b1010_1010,
      0xAAAA_AAAA_AAAA_AAAA,
      0xFFFFFFFFFFFFFFFF
    ]

    for board <- boards do
      assert Bitboard.squares(board) == naive_squares(board)
    end
  end

  test "squares and least_square agree" do
    board = 0x00FF_FF00_0F0F_5555

    assert [least | _] = Bitboard.squares(board)
    assert Bitboard.least_square(board) == least
  end

  defp naive_least_square(board) do
    board
    |> naive_squares()
    |> List.first()
  end

  defp naive_squares(board) do
    for bit <- 0..63, (1 <<< bit &&& board) != 0, do: bit
  end
end
