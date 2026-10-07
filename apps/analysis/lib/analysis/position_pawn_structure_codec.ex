defmodule Analysis.PositionPawnStructureCodec do
  @moduledoc """
  Encodes exact pawn bitboards for PostgreSQL `bigint` storage.

  Chess bitboards are unsigned 64-bit integers. PostgreSQL `bigint` is signed,
  so values with bit 63 set are represented using their two's-complement
  signed value. Equality preserves all 64 bits.
  """

  alias Chess.PawnStructure

  @unsigned_64_modulus 18_446_744_073_709_551_616
  @maximum_unsigned_64 @unsigned_64_modulus - 1
  @maximum_signed_64 9_223_372_036_854_775_807

  @type encoded :: {
          integer(),
          integer()
        }

  @spec encode(PawnStructure.t()) ::
          {:ok, encoded()}
          | {:error, :invalid_pawn_structure}
  def encode(%PawnStructure{white: white, black: black}) do
    with {:ok, white} <-
           encode_bitboard(white),
         {:ok, black} <-
           encode_bitboard(black) do
      {:ok,
       {
         white,
         black
       }}
    end
  end

  def encode(_structure) do
    {:error, :invalid_pawn_structure}
  end

  defp encode_bitboard(value)
       when is_integer(value) and value >= 0 and value <= @maximum_unsigned_64 do
    if value <= @maximum_signed_64 do
      {:ok, value}
    else
      {:ok,
       value -
         @unsigned_64_modulus}
    end
  end

  defp encode_bitboard(_value) do
    {:error, :invalid_pawn_structure}
  end
end
