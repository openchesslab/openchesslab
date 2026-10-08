defmodule Features.Chess.Zobrist do
  @moduledoc """
  Deterministic Zobrist hashing for positions.

  Keys are generated with SplitMix64 from fixed constants, so hashes are
  stable across OTP versions and can be persisted or compared between
  deployments.
  """

  import Bitwise

  alias Features.Chess.{Bitboard, Board, Square}

  @mask 0xFFFFFFFFFFFFFFFF

  @colors [:white, :black]
  @types [:pawns, :knights, :bishops, :rooks, :queens, :kings]

  {piece_keys, side_key, castling_keys, en_passant_keys} =
    (fn ->
       mix = fn x ->
         z = x + 0x9E3779B97F4A7C15
         z = z &&& @mask
         z = bxor(z, z >>> 30) * 0xBF58476D1CE4E5B9
         z = z &&& @mask
         z = bxor(z, z >>> 27) * 0x94D049BB133111EB
         z = z &&& @mask
         bxor(z, z >>> 31)
       end

       piece_keys =
         for {color, color_index} <- Enum.with_index(@colors),
             {type, type_index} <- Enum.with_index(@types),
             square <- 0..63,
             into: %{} do
           {{color, type, square}, mix.(color_index * 384 + type_index * 64 + square)}
         end

       castling_keys = for rights <- 0..15, into: %{}, do: {rights, mix.(769 + rights)}
       en_passant_keys = for file <- 0..7, into: %{}, do: {file, mix.(785 + file)}

       {piece_keys, mix.(768), castling_keys, en_passant_keys}
     end).()

  @piece_keys piece_keys
  @side_key side_key
  @castling_keys castling_keys
  @en_passant_keys en_passant_keys

  @doc "Zobrist hash of `board` as a 64-bit unsigned integer."
  @spec hash(Board.t()) :: non_neg_integer()
  def hash(board) do
    pieces_hash =
      Enum.reduce(board.pieces, 0, fn {{color, type}, bitboard}, acc ->
        Enum.reduce(Bitboard.squares(bitboard), acc, fn square, acc ->
          bxor(acc, Map.fetch!(@piece_keys, {color, type, square}))
        end)
      end)

    en_passant_hash =
      case board.en_passant do
        nil -> 0
        square -> Map.fetch!(@en_passant_keys, Square.file(square))
      end

    side_hash = if board.side_to_move == :white, do: @side_key, else: 0

    bxor(pieces_hash, Map.fetch!(@castling_keys, board.castling))
    |> bxor(en_passant_hash)
    |> bxor(side_hash)
  end
end
