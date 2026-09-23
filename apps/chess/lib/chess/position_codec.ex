defmodule Chess.PositionCodec do
  @moduledoc """
  Encodes a chess position into a deterministic binary representation.
  """

  alias Chess.Position

  @record_size 67

  def encode(%Position{} = position) do
    board =
      position.board
      |> Tuple.to_list()
      |> Enum.map(&encode_piece/1)
      |> IO.iodata_to_binary()

    <<board::binary, encode_side_to_move(position.side_to_move),
      encode_castling_rights(position.castling_rights), encode_en_passant(position.en_passant)>>
  end

  @spec decode(binary()) ::
          {:ok, Position.t()}
          | {:error, :invalid_record_size}
          | {:error, {:invalid_piece, byte()}}
          | {:error, {:invalid_side_to_move, byte()}}
          | {:error, {:invalid_castling_rights, byte()}}
          | {:error, {:invalid_en_passant, byte()}}
  def decode(encoded)
      when is_binary(encoded) do
    if byte_size(encoded) == @record_size do
      <<
        board::binary-size(64),
        side_to_move,
        castling_rights,
        en_passant
      >> = encoded

      with {:ok, board} <-
             decode_board(board),
           {:ok, side_to_move} <-
             decode_side_to_move(side_to_move),
           {:ok, castling_rights} <-
             decode_castling_rights(castling_rights),
           {:ok, en_passant} <-
             decode_en_passant(en_passant) do
        {:ok,
         Position.new(
           board: board,
           side_to_move: side_to_move,
           castling_rights: castling_rights,
           en_passant: en_passant
         )}
      end
    else
      {:error, :invalid_record_size}
    end
  end

  defp decode_board(encoded) do
    encoded
    |> :binary.bin_to_list()
    |> Enum.reduce_while(
      {:ok, []},
      fn value, {:ok, pieces} ->
        case decode_piece(value) do
          {:ok, piece} ->
            {:cont, {:ok, [piece | pieces]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, pieces} ->
        {:ok,
         pieces
         |> Enum.reverse()
         |> List.to_tuple()}

      error ->
        error
    end
  end

  defp decode_piece(0), do: {:ok, nil}

  defp decode_piece(1), do: {:ok, {:white, :pawn}}
  defp decode_piece(2), do: {:ok, {:white, :knight}}
  defp decode_piece(3), do: {:ok, {:white, :bishop}}
  defp decode_piece(4), do: {:ok, {:white, :rook}}
  defp decode_piece(5), do: {:ok, {:white, :queen}}
  defp decode_piece(6), do: {:ok, {:white, :king}}

  defp decode_piece(7), do: {:ok, {:black, :pawn}}
  defp decode_piece(8), do: {:ok, {:black, :knight}}
  defp decode_piece(9), do: {:ok, {:black, :bishop}}
  defp decode_piece(10), do: {:ok, {:black, :rook}}
  defp decode_piece(11), do: {:ok, {:black, :queen}}
  defp decode_piece(12), do: {:ok, {:black, :king}}

  defp decode_piece(value),
    do: {:error, {:invalid_piece, value}}

  defp decode_side_to_move(0),
    do: {:ok, :white}

  defp decode_side_to_move(1),
    do: {:ok, :black}

  defp decode_side_to_move(value),
    do: {:error, {:invalid_side_to_move, value}}

  defp decode_castling_rights(value)
       when value in 0..15 do
    rights =
      []
      |> maybe_decode_castling_right(
        value,
        :white_kingside,
        0
      )
      |> maybe_decode_castling_right(
        value,
        :white_queenside,
        1
      )
      |> maybe_decode_castling_right(
        value,
        :black_kingside,
        2
      )
      |> maybe_decode_castling_right(
        value,
        :black_queenside,
        3
      )
      |> MapSet.new()

    {:ok, rights}
  end

  defp decode_castling_rights(value),
    do: {:error, {:invalid_castling_rights, value}}

  defp maybe_decode_castling_right(
         rights,
         value,
         right,
         bit
       ) do
    if Bitwise.band(
         value,
         Bitwise.bsl(1, bit)
       ) != 0 do
      [right | rights]
    else
      rights
    end
  end

  defp decode_en_passant(255),
    do: {:ok, nil}

  defp decode_en_passant(square)
       when square in 0..63,
       do: {:ok, square}

  defp decode_en_passant(value),
    do: {:error, {:invalid_en_passant, value}}

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
