defmodule Chess.Notation.FEN do
  @moduledoc """
  Parses Forsyth-Edwards Notation into an OpenChessLab position.

  Halfmove and fullmove counters are parsed and validated separately
  because they are game context rather than position identity.

  OpenChessLab only retains an en-passant target when an en-passant
  capture is actually available. A syntactically valid FEN target for
  which no adjacent pawn can capture is therefore normalized to `nil`.
  """

  alias Chess.Board
  alias Chess.Position
  alias Chess.Square

  @type parsed :: %{
          position: Position.t(),
          halfmove_clock: non_neg_integer(),
          fullmove_number: pos_integer()
        }

  @spec parse(String.t()) ::
          {:ok, parsed()}
          | {:error, :invalid_fen}
  def parse(fen) when is_binary(fen) do
    case String.split(
           fen,
           ~r/\s+/,
           trim: true
         ) do
      [
        placement,
        active_color,
        castling,
        en_passant,
        halfmove_clock,
        fullmove_number
      ] ->
        with {:ok, board} <-
               parse_board(placement),
             {:ok, side_to_move} <-
               parse_side_to_move(active_color),
             {:ok, castling_rights} <-
               parse_castling_rights(castling),
             {:ok, en_passant} <-
               parse_en_passant(
                 en_passant,
                 board,
                 side_to_move
               ),
             {:ok, halfmove_clock} <-
               parse_non_negative_integer(halfmove_clock),
             {:ok, fullmove_number} <-
               parse_positive_integer(fullmove_number) do
          position =
            Position.new(
              board: board,
              side_to_move: side_to_move,
              castling_rights: castling_rights,
              en_passant: en_passant
            )

          case Position.validate(position) do
            :ok ->
              {:ok,
               %{
                 position: position,
                 halfmove_clock: halfmove_clock,
                 fullmove_number: fullmove_number
               }}

            {:error, _reasons} ->
              {:error, :invalid_fen}
          end
        end

      _fields ->
        {:error, :invalid_fen}
    end
  end

  def parse(_fen) do
    {:error, :invalid_fen}
  end

  defp parse_board(placement) do
    ranks =
      String.split(
        placement,
        "/",
        trim: false
      )

    if length(ranks) == 8 do
      ranks
      |> Enum.with_index()
      |> Enum.reduce_while(
        {:ok, Board.empty()},
        fn {rank, rank_index}, {:ok, board} ->
          case parse_rank(
                 rank,
                 rank_index,
                 board
               ) do
            {:ok, board} ->
              {:cont, {:ok, board}}

            {:error, :invalid_fen} ->
              {:halt, {:error, :invalid_fen}}
          end
        end
      )
    else
      {:error, :invalid_fen}
    end
  end

  defp parse_rank(rank, rank_index, board) do
    rank
    |> String.to_charlist()
    |> Enum.reduce_while(
      {:ok, board, 0},
      fn character, {:ok, board, file_index} ->
        cond do
          character in ?1..?8 ->
            next_file_index =
              file_index +
                character -
                ?0

            if next_file_index <= 8 do
              {:cont,
               {
                 :ok,
                 board,
                 next_file_index
               }}
            else
              {:halt, {:error, :invalid_fen}}
            end

          file_index >= 8 ->
            {:halt, {:error, :invalid_fen}}

          true ->
            case piece(character) do
              nil ->
                {:halt, {:error, :invalid_fen}}

              piece ->
                square =
                  (7 - rank_index) * 8 +
                    file_index

                {:cont,
                 {
                   :ok,
                   Board.put(
                     board,
                     square,
                     piece
                   ),
                   file_index + 1
                 }}
            end
        end
      end
    )
    |> case do
      {:ok, board, 8} ->
        {:ok, board}

      _result ->
        {:error, :invalid_fen}
    end
  end

  defp piece(?P), do: {:white, :pawn}
  defp piece(?N), do: {:white, :knight}
  defp piece(?B), do: {:white, :bishop}
  defp piece(?R), do: {:white, :rook}
  defp piece(?Q), do: {:white, :queen}
  defp piece(?K), do: {:white, :king}

  defp piece(?p), do: {:black, :pawn}
  defp piece(?n), do: {:black, :knight}
  defp piece(?b), do: {:black, :bishop}
  defp piece(?r), do: {:black, :rook}
  defp piece(?q), do: {:black, :queen}
  defp piece(?k), do: {:black, :king}

  defp piece(_character), do: nil

  defp parse_side_to_move("w") do
    {:ok, :white}
  end

  defp parse_side_to_move("b") do
    {:ok, :black}
  end

  defp parse_side_to_move(_side_to_move) do
    {:error, :invalid_fen}
  end

  defp parse_castling_rights("-") do
    {:ok, MapSet.new()}
  end

  defp parse_castling_rights(castling) do
    characters =
      String.to_charlist(castling)

    if characters != [] and
         Enum.uniq(characters) ==
           characters do
      characters
      |> Enum.reduce_while(
        {:ok, MapSet.new()},
        fn character, {:ok, rights} ->
          case castling_right(character) do
            nil ->
              {:halt, {:error, :invalid_fen}}

            right ->
              {:cont,
               {
                 :ok,
                 MapSet.put(
                   rights,
                   right
                 )
               }}
          end
        end
      )
    else
      {:error, :invalid_fen}
    end
  end

  defp castling_right(?K), do: :white_kingside
  defp castling_right(?Q), do: :white_queenside
  defp castling_right(?k), do: :black_kingside
  defp castling_right(?q), do: :black_queenside
  defp castling_right(_character), do: nil

  defp parse_en_passant("-", _board, _side_to_move) do
    {:ok, nil}
  end

  defp parse_en_passant(square_name, board, side_to_move) do
    case Square.from_algebraic(square_name) do
      square when is_integer(square) ->
        normalize_en_passant(
          square,
          board,
          side_to_move
        )

      {:error, :invalid_square} ->
        {:error, :invalid_fen}
    end
  end

  defp normalize_en_passant(target, board, :white) when target in 40..47 do
    moved_pawn_square =
      target - 8

    source_square =
      target + 8

    if Board.get(board, target) == nil and
         Board.get(
           board,
           moved_pawn_square
         ) ==
           {:black, :pawn} and
         Board.get(
           board,
           source_square
         ) ==
           nil do
      {:ok,
       if(
         adjacent_pawn?(
           board,
           moved_pawn_square,
           {:white, :pawn}
         ),
         do: target
       )}
    else
      {:error, :invalid_fen}
    end
  end

  defp normalize_en_passant(target, board, :black) when target in 16..23 do
    moved_pawn_square =
      target + 8

    source_square =
      target - 8

    if Board.get(board, target) == nil and
         Board.get(
           board,
           moved_pawn_square
         ) ==
           {:white, :pawn} and
         Board.get(
           board,
           source_square
         ) ==
           nil do
      {:ok,
       if(
         adjacent_pawn?(
           board,
           moved_pawn_square,
           {:black, :pawn}
         ),
         do: target
       )}
    else
      {:error, :invalid_fen}
    end
  end

  defp normalize_en_passant(_target, _board, _side_to_move) do
    {:error, :invalid_fen}
  end

  defp adjacent_pawn?(board, pawn_square, pawn) do
    file =
      rem(
        pawn_square,
        8
      )

    left? =
      file > 0 and
        Board.get(
          board,
          pawn_square - 1
        ) ==
          pawn

    right? =
      file < 7 and
        Board.get(
          board,
          pawn_square + 1
        ) ==
          pawn

    left? or right?
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""}
      when integer >= 0 ->
        {:ok, integer}

      _result ->
        {:error, :invalid_fen}
    end
  end

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {integer, ""}
      when integer > 0 ->
        {:ok, integer}

      _result ->
        {:error, :invalid_fen}
    end
  end
end
