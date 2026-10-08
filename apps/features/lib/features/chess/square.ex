defmodule Features.Chess.Square do
  @moduledoc """
  Chess squares as integers `0..63` in little-endian rank-file order:
  `a1 = 0`, `h1 = 7`, `a8 = 56`, `h8 = 63`.
  """

  @files ~w(a b c d e f g h)

  @doc "Parse algebraic notation (`\"e4\"`) into a square index."
  def parse(<<file, rank>>) when file in ?a..?h and rank in ?1..?8 do
    (rank - ?1) * 8 + (file - ?a)
  end

  def parse(value) when is_binary(value) do
    raise ArgumentError, "invalid square: #{inspect(value)}"
  end

  @doc "Convert a square index to algebraic notation (`\"e4\"`)."
  def to_string(square) when square in 0..63 do
    "#{Enum.at(@files, rem(square, 8))}#{div(square, 8) + 1}"
  end

  @doc "File index (0 = a, 7 = h)."
  def file(square), do: rem(square, 8)

  @doc "Rank index (0 = 1st rank, 7 = 8th rank)."
  def rank(square), do: div(square, 8)

  @doc "Square index from file and rank index."
  def new(file, rank) when file in 0..7 and rank in 0..7 do
    rank * 8 + file
  end
end
