defmodule Chess.Move do
  @moduledoc """
  Represents a chess move.

  A move consists of a source square, a destination square, and optionally
  a promotion piece.
  """

  @type promotion :: :queen | :rook | :bishop | :knight

  @type t :: %__MODULE__{
          from: Chess.Square.t(),
          to: Chess.Square.t(),
          promotion: promotion() | nil
        }

  @enforce_keys [:from, :to]
  defstruct [:from, :to, :promotion]

  @spec new(Chess.Square.t(), Chess.Square.t(), promotion() | nil) :: t()
  def new(from, to, promotion \\ nil) do
    %__MODULE__{
      from: from,
      to: to,
      promotion: promotion
    }
  end
end
