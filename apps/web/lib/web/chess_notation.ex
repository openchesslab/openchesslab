defmodule Web.ChessNotation do
  @moduledoc """
  Formats chess transitions for presentation in a locale.

  Canonical SAN remains language-independent in the chess and analysis
  domains. This module localizes piece letters for the user interface.
  """

  alias Analysis.Transition
  alias Analysis.TransitionNotation
  alias Chess.Position

  @spec format(Position.t(), Transition.t(), String.t()) ::
          {:ok, String.t()} | :not_applicable | {:error, :illegal_move}
  def format(%Position{} = position, transition, locale) do
    case TransitionNotation.format(position, transition) do
      {:ok, notation} ->
        {:ok, localize(notation, transition, position, locale)}

      other ->
        other
    end
  end

  defp localize(notation, _transition, _position, "en") do
    notation
  end

  defp localize(
         notation,
         {:move, move},
         position,
         "nl"
       ) do
    {_color, piece} = Position.piece_at(position, move.from)

    notation
    |> localize_moving_piece(piece)
    |> localize_promotion(move.promotion)
  end

  defp localize(notation, _transition, _position, _locale) do
    notation
  end

  defp localize_moving_piece(notation, :pawn), do: notation

  defp localize_moving_piece(notation, piece) do
    String.replace_prefix(
      notation,
      canonical_piece_letter(piece),
      dutch_piece_letter(piece)
    )
  end

  defp localize_promotion(notation, nil), do: notation

  defp localize_promotion(notation, piece) do
    String.replace(
      notation,
      "=" <> canonical_piece_letter(piece),
      "=" <> dutch_piece_letter(piece)
    )
  end

  defp canonical_piece_letter(:king), do: "K"
  defp canonical_piece_letter(:queen), do: "Q"
  defp canonical_piece_letter(:rook), do: "R"
  defp canonical_piece_letter(:bishop), do: "B"
  defp canonical_piece_letter(:knight), do: "N"

  defp dutch_piece_letter(:king), do: "K"
  defp dutch_piece_letter(:queen), do: "D"
  defp dutch_piece_letter(:rook), do: "T"
  defp dutch_piece_letter(:bishop), do: "L"
  defp dutch_piece_letter(:knight), do: "P"
end
