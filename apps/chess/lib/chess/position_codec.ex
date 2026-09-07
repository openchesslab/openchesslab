defmodule Chess.PositionCodec do
  @moduledoc """
  Encodes a chess position into a deterministic binary representation.
  """

  alias Chess.Position

  def encode(%Position{} = position) do
    board =
      position.board
      |> Tuple.to_list()
      |> Enum.map(&encode_piece/1)
      |> IO.iodata_to_binary()

    <<board::binary, encode_side_to_move(position.side_to_move),
      encode_castling_rights(position.castling_rights), encode_en_passant(position.en_passant)>>
  end

  defp encode_piece(nil), do: 0

  defp encode_piece({:white, :pawn}), do: 1
  defp encode_piece({:white, :knight}), do: 2
  defp encode_piece({:white, :bishop}), do: 3
  defp encode_piece({:white, :rook}), do: 4
  defp encode_piece({:white, :queen}), do: 5
  defp encode_piece({:white, :king}), do: 6

  defp encode_piece({:black, :pawn}), do: 7
  defp encode_piece({:black, :knight}), do: 8
  defp encode_piece({:black, :bishop}), do: 9
  defp encode_piece({:black, :rook}), do: 10
  defp encode_piece({:black, :queen}), do: 11
  defp encode_piece({:black, :king}), do: 12

  defp encode_side_to_move(:white), do: 0
  defp encode_side_to_move(:black), do: 1

  defp encode_castling_rights(rights) do
    0
    |> maybe_set_bit(rights, :white_kingside, 0)
    |> maybe_set_bit(rights, :white_queenside, 1)
    |> maybe_set_bit(rights, :black_kingside, 2)
    |> maybe_set_bit(rights, :black_queenside, 3)
  end

  defp maybe_set_bit(value, rights, right, bit) do
    if MapSet.member?(rights, right) do
      Bitwise.bor(value, Bitwise.bsl(1, bit))
    else
      value
    end
  end

  defp encode_en_passant(nil), do: 255
  defp encode_en_passant(square), do: square
end
