defmodule Chess.PawnStructure do
  @moduledoc """
  Exact pawn occupancy for both colors.

  Pawn structure intentionally excludes every other aspect of position
  identity, including side to move, castling rights, en passant state and
  non-pawn pieces.
  """

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
end
