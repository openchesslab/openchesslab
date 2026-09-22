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
    if move in Position.legal_moves(position) do
      {:ok, format_legal_move(position, move)}
    else
      {:error, :illegal_move}
    end
  end

  defp format_legal_move(position, %Move{} = move) do
    {_color, piece} = Position.piece_at(position, move.from)

    destination = Square.to_algebraic(move.to)
    capture? = capture?(position, move)

    case piece do
      :pawn ->
        format_pawn_move(move, destination, capture?)

      piece ->
        piece_letter(piece) <>
          capture_marker(capture?) <>
          destination
    end
  end

  defp format_pawn_move(move, destination, true) do
    source = Square.to_algebraic(move.from)
    source_file = String.first(source)

    source_file <> "x" <> destination
  end

  defp format_pawn_move(_move, destination, false) do
    destination
  end

  defp capture?(position, move) do
    Position.piece_at(position, move.to) != nil
  end

  defp capture_marker(true), do: "x"
  defp capture_marker(false), do: ""

  defp piece_letter(:king), do: "K"
  defp piece_letter(:queen), do: "Q"
  defp piece_letter(:rook), do: "R"
  defp piece_letter(:bishop), do: "B"
  defp piece_letter(:knight), do: "N"
end
