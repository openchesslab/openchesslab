defmodule Features.Chess.Bitboard do
  @moduledoc """
  Bitboard helpers: iteration over set squares and least-significant-bit
  lookup, implemented with pure integer arithmetic.
  """

  import Bitwise

  @mask 0xFFFFFFFFFFFFFFFF
  @de_bruijn 0x022FDD63CC95386D

  # Multiplying an isolated power of two by a de Bruijn sequence scatters
  # its bit position into a unique 6-bit fingerprint (bits 58..63); the
  # table maps that fingerprint back to the bit position.
  @de_bruijn_index (fn ->
                      table =
                        for bit <- 0..63, into: %{} do
                          fingerprint = ((1 <<< bit) * @de_bruijn &&& @mask) >>> 58
                          {fingerprint, bit}
                        end

                      for fingerprint <- 0..63 do
                        Map.fetch!(table, fingerprint)
                      end
                      |> List.to_tuple()
                    end).()

  @doc "Index of the least significant set bit (0..63). Raises on 0."
  @spec least_square(pos_integer()) :: 0..63
  def least_square(bitboard) when bitboard > 0 do
    isolob = bitboard &&& -bitboard
    fingerprint = (isolob * @de_bruijn &&& @mask) >>> 58
    elem(@de_bruijn_index, fingerprint)
  end

  @doc "All set squares in ascending order."
  @spec squares(non_neg_integer()) :: [0..63]
  def squares(0), do: []

  def squares(bitboard) do
    square = least_square(bitboard)
    [square | squares(bitboard &&& bitboard - 1)]
  end
end
