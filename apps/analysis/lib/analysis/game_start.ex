defmodule Analysis.GameStart do
  @moduledoc """
  Describes the game context of the root position.

  The chess position itself determines which side is to move.
  `fullmove_number` determines the move number assigned to that
  root occurrence.

  This context belongs to a game, not to position identity.
  """

  @type t :: %__MODULE__{
          fullmove_number: pos_integer()
        }

  @enforce_keys [:fullmove_number]
  defstruct [:fullmove_number]

  @spec new(pos_integer()) :: t()
  def new(fullmove_number)
      when is_integer(fullmove_number) and fullmove_number > 0 do
    %__MODULE__{
      fullmove_number: fullmove_number
    }
  end

  @spec standard() :: t()
  def standard do
    new(1)
  end

  @spec fullmove_number(t()) :: pos_integer()
  def fullmove_number(%__MODULE__{fullmove_number: fullmove_number}) do
    fullmove_number
  end
end
