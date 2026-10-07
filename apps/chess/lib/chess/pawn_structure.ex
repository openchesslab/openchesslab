defmodule Chess.PawnStructure do
  @moduledoc """
  Exact pawn occupancy for both colors.

  Pawn structure intentionally excludes every other aspect of position
  identity, including side to move, castling rights, en passant state and
  non-pawn pieces.

  Color reversal swaps White and Black while reflecting ranks so pawn
  direction remains meaningful. For example, a White pawn on d4 becomes
  a Black pawn on d5.
  """

  import Bitwise

  alias Chess.Bitboard
  alias Chess.Position

  @enforce_keys [
    :white,
    :black
  ]

  defstruct [
    :white,
    :black
  ]

  @type t :: %__MODULE__{
          white: non_neg_integer(),
          black: non_neg_integer()
        }

  @spec from_position(Position.t()) :: t()
  def from_position(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> from_bitboard()
  end

  @spec from_bitboard(Bitboard.t()) :: t()
  def from_bitboard(%Bitboard{} = board) do
    %__MODULE__{
      white: board.white_pawns,
      black: board.black_pawns
    }
  end

  @doc """
  Returns the same pawn structure from the opposite color perspective.

  Colors are swapped and ranks are reflected:

    * rank 1 <-> rank 8
    * rank 2 <-> rank 7
    * rank 3 <-> rank 6
    * rank 4 <-> rank 5

  Files are preserved.
  """
  @spec color_reversed(t()) :: t()
  def color_reversed(%__MODULE__{white: white, black: black}) do
    %__MODULE__{
      white: flip_ranks(black),
      black: flip_ranks(white)
    }
  end

  defp flip_ranks(bitboard) do
    0..7
    |> Enum.reduce(
      0,
      fn rank, reversed ->
        rank_bits =
          bitboard
          |> bsr(rank * 8)
          |> band(0xFF)

        bor(
          reversed,
          bsl(
            rank_bits,
            (7 - rank) * 8
          )
        )
      end
    )
  end
end
