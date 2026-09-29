defmodule Analysis.GameContentCodec do
  @moduledoc """
  Encodes canonical game content into a stable, reversible binary format.

  Format `OCLGAME1`:

    * 8 bytes format identifier
    * 8 bytes initial PositionDB position ID
    * 4 bytes move count
    * 3 bytes per move:
      * source square
      * destination square
      * promotion code

  The same canonical encoding is used as input for game fingerprints
  and can later be stored directly by durable GameDB storage.
  """

  @behaviour GameDB.RecordCodec

  alias Analysis.GameContent
  alias Chess.Move

  @format_id <<"OCLGAME1">>
  @format_size byte_size(@format_id)

  @max_position_id 0xFFFF_FFFF_FFFF_FFFF
  @max_move_count 0xFFFF_FFFF

  @type encoded :: binary()

  @spec format_id() :: binary()
  def format_id do
    @format_id
  end

  @impl true
  @spec encode(term()) ::
          {:ok, encoded()}
          | {:error, term()}
  def encode(%GameContent{
        initial_position_id: initial_position_id,
        moves: moves
      })
      when is_list(moves) do
    move_count =
      length(moves)

    with :ok <-
           validate_initial_position_id(initial_position_id),
         :ok <-
           validate_move_count(move_count),
         {:ok, encoded_moves} <-
           encode_moves(moves) do
      {:ok,
       <<
         @format_id::binary,
         initial_position_id::unsigned-big-64,
         move_count::unsigned-big-32,
         encoded_moves::binary
       >>}
    end
  end

  def encode(_content) do
    {:error, :invalid_game_content}
  end

  @impl true
  @spec decode(binary()) ::
          {:ok, GameContent.t()}
          | {:error, term()}

  def decode(encoded)
      when is_binary(encoded) do
    case encoded do
      <<
        format_id::binary-size(@format_size),
        initial_position_id::unsigned-big-64,
        move_count::unsigned-big-32,
        encoded_moves::binary
      >> ->
        with :ok <-
               validate_format_id(format_id),
             :ok <-
               validate_initial_position_id(initial_position_id),
             :ok <-
               validate_encoded_moves_size(
                 encoded_moves,
                 move_count
               ),
             {:ok, moves} <-
               decode_moves(
                 encoded_moves,
                 []
               ) do
          {:ok,
           GameContent.new(
             initial_position_id,
             moves
           )}
        end

      _other ->
        {:error, :invalid_record}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_record}
  end

  defp validate_format_id(@format_id) do
    :ok
  end

  defp validate_format_id(_format_id) do
    {:error, :invalid_format}
  end

  defp validate_initial_position_id(initial_position_id)
       when is_integer(initial_position_id) and
              initial_position_id > 0 and
              initial_position_id <= @max_position_id do
    :ok
  end

  defp validate_initial_position_id(_initial_position_id) do
    {:error, :invalid_initial_position_id}
  end

  defp validate_move_count(move_count)
       when move_count <= @max_move_count do
    :ok
  end

  defp validate_encoded_moves_size(
         encoded_moves,
         move_count
       ) do
    if byte_size(encoded_moves) ==
         move_count * 3 do
      :ok
    else
      {:error, :invalid_record_size}
    end
  end

  defp encode_moves(moves) do
    moves
    |> Enum.reduce_while(
      {:ok, []},
      fn move, {:ok, encoded_moves} ->
        case encode_move(move) do
          {:ok, encoded_move} ->
            {:cont,
             {:ok,
              [
                encoded_move
                | encoded_moves
              ]}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    )
    |> case do
      {:ok, encoded_moves} ->
        {:ok,
         encoded_moves
         |> Enum.reverse()
         |> IO.iodata_to_binary()}

      {:error, _reason} = error ->
        error
    end
  end

  defp encode_move(%Move{
         from: from,
         to: to,
         promotion: promotion
       })
       when from in 0..63 and
              to in 0..63 do
    case promotion_code(promotion) do
      {:ok, promotion_code} ->
        {:ok,
         <<
           from,
           to,
           promotion_code
         >>}

      {:error, _reason} = error ->
        error
    end
  end

  defp encode_move(_move) do
    {:error, :invalid_move}
  end

  defp decode_moves(
         <<>>,
         reversed_moves
       ) do
    {:ok, Enum.reverse(reversed_moves)}
  end

  defp decode_moves(
         <<
           from,
           to,
           promotion_code,
           remaining::binary
         >>,
         reversed_moves
       ) do
    with :ok <-
           validate_square(from),
         :ok <-
           validate_square(to),
         {:ok, promotion} <-
           promotion_from_code(promotion_code) do
      decode_moves(
        remaining,
        [
          Move.new(
            from,
            to,
            promotion
          )
          | reversed_moves
        ]
      )
    end
  end

  defp decode_moves(
         _encoded_moves,
         _reversed_moves
       ) do
    {:error, :invalid_record}
  end

  defp validate_square(square)
       when square in 0..63 do
    :ok
  end

  defp validate_square(_square) do
    {:error, :invalid_move}
  end

  defp promotion_code(nil), do: {:ok, 0}
  defp promotion_code(:queen), do: {:ok, 1}
  defp promotion_code(:rook), do: {:ok, 2}
  defp promotion_code(:bishop), do: {:ok, 3}
  defp promotion_code(:knight), do: {:ok, 4}

  defp promotion_code(_promotion) do
    {:error, :invalid_promotion}
  end

  defp promotion_from_code(0), do: {:ok, nil}
  defp promotion_from_code(1), do: {:ok, :queen}
  defp promotion_from_code(2), do: {:ok, :rook}
  defp promotion_from_code(3), do: {:ok, :bishop}
  defp promotion_from_code(4), do: {:ok, :knight}

  defp promotion_from_code(_promotion_code) do
    {:error, :invalid_promotion}
  end
end
