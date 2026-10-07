defmodule Chess.PawnStructure.Difference do
  @moduledoc """
  Describes the directional occupancy difference between two pawn structures.

  Removed pawns are present in the source structure but absent from the target.
  Added pawns are absent from the source structure but present in the target.

  The difference can classify changes that correspond to one of the elementary
  pawn-structure transformations supported by `Chess.PawnStructure`.
  """

  import Bitwise

  @enforce_keys [
    :white_removed,
    :white_added,
    :black_removed,
    :black_added
  ]

  defstruct [
    :white_removed,
    :white_added,
    :black_removed,
    :black_added
  ]

  @type t :: %__MODULE__{
          white_removed: non_neg_integer(),
          white_added: non_neg_integer(),
          black_removed: non_neg_integer(),
          black_added: non_neg_integer()
        }

  @type color :: :white | :black

  @type classification ::
          :exact
          | :not_single_edit
          | {:single_pawn_removal, color(), Chess.Square.t()}
          | {:single_pawn_addition, color(), Chess.Square.t()}
          | {:single_rank_displacement, color(), Chess.Square.t(), Chess.Square.t()}
          | {:single_capture_like_displacement, color(), Chess.Square.t(), Chess.Square.t()}

  @doc """
  Classifies the difference when it represents at most one elementary edit.

  Supported elementary edits are:

    * removal of one pawn
    * addition of one pawn
    * displacement of one pawn by exactly one rank on the same file
    * displacement of one pawn by exactly one rank and one file

  `:exact` means there is no difference.

  `:not_single_edit` means the difference requires multiple elementary edits
  or contains a relocation outside the supported elementary geometry.
  """
  @spec classify(t()) :: classification()
  def classify(%__MODULE__{} = difference) do
    white_removed =
      pawn_squares(difference.white_removed)

    white_added =
      pawn_squares(difference.white_added)

    black_removed =
      pawn_squares(difference.black_removed)

    black_added =
      pawn_squares(difference.black_added)

    cond do
      white_removed == [] and
        white_added == [] and
        black_removed == [] and
          black_added == [] ->
        :exact

      black_removed == [] and
          black_added == [] ->
        classify_color(
          :white,
          white_removed,
          white_added
        )

      white_removed == [] and
          white_added == [] ->
        classify_color(
          :black,
          black_removed,
          black_added
        )

      true ->
        :not_single_edit
    end
  end

  defp classify_color(color, [square], []) do
    {
      :single_pawn_removal,
      color,
      square
    }
  end

  defp classify_color(color, [], [square]) do
    {
      :single_pawn_addition,
      color,
      square
    }
  end

  defp classify_color(color, [from], [to]) do
    cond do
      single_rank_displacement?(
        from,
        to
      ) ->
        {
          :single_rank_displacement,
          color,
          from,
          to
        }

      single_capture_like_displacement?(
        from,
        to
      ) ->
        {
          :single_capture_like_displacement,
          color,
          from,
          to
        }

      true ->
        :not_single_edit
    end
  end

  defp classify_color(_color, _removed, _added) do
    :not_single_edit
  end

  defp single_rank_displacement?(from, to) do
    square_file(from) ==
      square_file(to) and
      abs(
        square_rank(from) -
          square_rank(to)
      ) == 1
  end

  defp single_capture_like_displacement?(from, to) do
    abs(
      square_file(from) -
        square_file(to)
    ) == 1 and
      abs(
        square_rank(from) -
          square_rank(to)
      ) == 1
  end

  defp square_file(square) do
    rem(
      square,
      8
    )
  end

  defp square_rank(square) do
    div(
      square,
      8
    )
  end

  defp pawn_squares(pawns) do
    for square <- 0..63,
        band(
          pawns,
          bsl(
            1,
            square
          )
        ) != 0 do
      square
    end
  end
end
