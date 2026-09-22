defmodule Analysis.MoveContext do
  @moduledoc """
  Describes the move number and side for a ply in a game.

  The context is derived from the fullmove number and side to move
  at the root position, together with the ply depth from that root.
  """

  @type side :: :white | :black

  @type t :: %__MODULE__{
          fullmove_number: pos_integer(),
          side: side()
        }

  @enforce_keys [:fullmove_number, :side]
  defstruct [:fullmove_number, :side]

  @spec at(pos_integer(), side(), non_neg_integer()) :: t()
  def at(starting_fullmove_number, starting_side, ply_depth)
      when is_integer(starting_fullmove_number) and
             starting_fullmove_number > 0 and
             starting_side in [:white, :black] and
             is_integer(ply_depth) and
             ply_depth >= 0 do
    offset =
      case starting_side do
        :white -> ply_depth
        :black -> ply_depth + 1
      end

    %__MODULE__{
      fullmove_number: starting_fullmove_number + div(offset, 2),
      side: side_at(starting_side, ply_depth)
    }
  end

  defp side_at(side, ply_depth) when rem(ply_depth, 2) == 0 do
    side
  end

  defp side_at(:white, _ply_depth), do: :black
  defp side_at(:black, _ply_depth), do: :white
end
