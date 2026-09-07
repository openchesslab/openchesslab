defmodule Chess.Square do
  @moduledoc """
  Represents a square on a chess board as an integer from 0 to 63.

  Squares are numbered from a1 to h8, rank by rank:

      a1 = 0   b1 = 1   ... h1 = 7
      a2 = 8   b2 = 9   ... h2 = 15
      ...
      a8 = 56  b8 = 57  ... h8 = 63
  """

  @type t :: 0..63

  @files ?a..?h
  @ranks ?1..?8

  @spec from_algebraic(String.t()) :: t() | {:error, :invalid_square}
  def from_algebraic(<<file, rank>>) when file in @files and rank in @ranks do
    (rank - ?1) * 8 + (file - ?a)
  end

  def from_algebraic(_), do: {:error, :invalid_square}

  @spec to_algebraic(t()) :: String.t()
  def to_algebraic(square) when square in 0..63 do
    file = rem(square, 8) + ?a
    rank = div(square, 8) + ?1

    <<file, rank>>
  end
end
