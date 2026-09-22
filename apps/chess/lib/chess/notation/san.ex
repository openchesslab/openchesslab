defmodule Chess.Notation.SAN do
  @moduledoc """
  Formats legal chess moves using Standard Algebraic Notation (SAN).

  SAN is canonical chess notation and is not localized.
  """

  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  @spec format(Position.t(), Move.t()) ::
          {:ok, String.t()} | {:error, :illegal_move}
  def format(%Position{} = position, %Move{} = move) do
    legal_moves = Position.legal_moves(position)

    if move in legal_moves do
      {:ok, format_legal_move(position, move, legal_moves)}
    else
      {:error, :illegal_move}
    end
  end

  defp format_legal_move(position, %Move{} = move, legal_moves) do
    {_color, piece} = Position.piece_at(position, move.from)

    notation =
      if castle?(piece, move) do
        format_castle(move)
      else
        destination = Square.to_algebraic(move.to)
        capture? = capture?(position, piece, move)

        case piece do
          :pawn ->
            format_pawn_move(
              move,
              destination,
              capture?
            )

          piece ->
            piece_letter(piece) <>
              disambiguation(
                position,
                move,
                piece,
                legal_moves
              ) <>
              capture_marker(capture?) <>
              destination
        end
      end

    notation <> check_suffix(position, move)
  end

  defp castle?(:king, %Move{from: from, to: to}) do
    abs(to - from) == 2
  end

  defp castle?(_piece, _move), do: false

  defp format_castle(%Move{from: from, to: to})
       when to > from do
    "O-O"
  end

  defp format_castle(%Move{}) do
    "O-O-O"
  end

  defp format_pawn_move(move, destination, capture?) do
    prefix =
      if capture? do
        move.from
        |> Square.to_algebraic()
        |> String.first()
        |> Kernel.<>("x")
      else
        ""
      end

    prefix <>
      destination <>
      promotion_suffix(move.promotion)
  end

  defp disambiguation(position, move, piece, legal_moves) do
    alternatives =
      Enum.filter(legal_moves, fn candidate ->
        candidate != move and
          candidate.to == move.to and
          Position.piece_at(position, candidate.from) ==
            {position.side_to_move, piece}
      end)

    case alternatives do
      [] ->
        ""

      alternatives ->
        source = Square.to_algebraic(move.from)
        source_file = String.first(source)
        source_rank = String.last(source)

        same_file? =
          Enum.any?(alternatives, fn candidate ->
            rem(candidate.from, 8) == rem(move.from, 8)
          end)

        same_rank? =
          Enum.any?(alternatives, fn candidate ->
            div(candidate.from, 8) == div(move.from, 8)
          end)

        cond do
          not same_file? ->
            source_file

          not same_rank? ->
            source_rank

          true ->
            source
        end
    end
  end

  defp capture?(position, :pawn, move) do
    Position.piece_at(position, move.to) != nil or
      en_passant_capture?(position, move)
  end

  defp capture?(position, _piece, move) do
    Position.piece_at(position, move.to) != nil
  end

  defp en_passant_capture?(
         %Position{en_passant: target},
         %Move{to: target}
       )
       when not is_nil(target) do
    true
  end

  defp en_passant_capture?(_position, _move), do: false

  defp promotion_suffix(nil), do: ""

  defp promotion_suffix(piece) do
    "=" <> piece_letter(piece)
  end

  defp check_suffix(position, move) do
    {:ok, next_position} = Position.apply_move(position, move)
    opponent = next_position.side_to_move

    cond do
      Position.checkmate?(next_position, opponent) ->
        "#"

      Position.in_check?(next_position, opponent) ->
        "+"

      true ->
        ""
    end
  end

  defp capture_marker(true), do: "x"
  defp capture_marker(false), do: ""

  defp piece_letter(:king), do: "K"
  defp piece_letter(:queen), do: "Q"
  defp piece_letter(:rook), do: "R"
  defp piece_letter(:bishop), do: "B"
  defp piece_letter(:knight), do: "N"
end
